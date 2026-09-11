//! Flutter embedder callbacks and the renderer's runtime-facing handler.

use super::*;

#[path = "handler/gpu_deadline.rs"]
mod gpu_deadline;
#[path = "handler/open_gl.rs"]
mod open_gl;

#[derive(Clone, Copy, Debug)]
struct PendingOutputPresentation {
    view_id: i64,
    framebuffer: u32,
    presentation_time_nanos: u64,
}

/// Accounting returned by `destroy_targets_after_engine_failure` so the
/// caller can log exactly which resources still could not be reclaimed and
/// had to outlive the failed engine with the process.
#[derive(Clone, Copy, Debug, Default)]
pub(in crate::flutter_runtime) struct EngineFailureTeardown {
    /// Texture sources and sampled-buffer guards dropped without needing the
    /// engine or a GL context.
    pub released_sources: usize,
    pub released_sampled_buffers: usize,
    /// Reusable lease tokens freed from the pool; in-flight leases stay owned
    /// by surviving engine frame callbacks.
    pub released_lease_tokens: usize,
    /// Cache entries pushed into the retired queue during teardown.
    pub queued_cached_bindings: usize,
    /// True when the context-bound teardown ran to completion. False means a
    /// surviving engine worker still held the render context or a teardown
    /// mutex, and the retained counts below include what it still owned.
    pub gl_teardown_completed: bool,
    /// GPU objects still owned after the teardown attempt.
    pub retained_targets: usize,
    pub retained_depth_stencils: usize,
    pub retained_shader_blit: bool,
    pub retained_external_bindings: usize,
    /// External texture leases still owned by Flutter through `user_data`
    /// pointers whose destruction_callback never ran after the failed
    /// shutdown. These stay leaked by contract — freeing one would leave a
    /// dangling pointer a surviving worker may still call back through —
    /// but they are counted here.
    pub inflight_external_leases: usize,
    /// Lower-bound estimate of GPU memory still referenced by the retained
    /// objects above.
    pub retained_estimated_bytes: usize,
}

pub(in crate::flutter_runtime) struct FlutterGlHandler {
    render_context: Mutex<ContextBinding>,
    resource_context: Mutex<ContextBinding>,
    display: Arc<EGLDisplayHandle>,
    gl: GlApi,
    targets: Mutex<Vec<GlTarget>>,
    shader_blit: Mutex<Option<ShaderBlit>>,
    depth_stencils: Mutex<Vec<u32>>,
    broker: Mutex<OutputBufferBroker>,
    pending_output_presentation: Mutex<Option<PendingOutputPresentation>>,
    gpu_deadline_hints: gpu_deadline::GpuDeadlineHints,
    external_texture_sources: Mutex<HashMap<i64, ExternalTextureSlot>>,
    raster_sampled_buffers: Mutex<Vec<SampledBufferHold>>,
    raster_sampled_feedback: Mutex<Vec<crate::surface_feedback::SurfaceFeedback>>,
    sampled_buffer_release_fence: Mutex<Option<OwnedFd>>,
    sampled_buffer_batch_pool: Arc<SampledBufferBatchPool>,
    dmabuf_texture_cache: Mutex<PartitionedRecencyCache<i64, Dmabuf, Arc<CachedTextureBinding>>>,
    shm_texture_cache: Mutex<RecencyCache<(i64, u64), Arc<CachedTextureBinding>>>,
    retired_external_bindings: Arc<RetiredExternalBindingQueue>,
    retired_external_binding_scratch: Mutex<Vec<ExternalTextureBinding>>,
    external_texture_lease_pool: Arc<ExternalTextureLeasePool>,
    prepared_external_texture: Mutex<Option<PreparedExternalTexture>>,
    external_texture_resource_budget: Arc<ExternalTextureResourceBudget>,
    pending_vsync_batons: Mutex<PendingVsyncBatons>,
    platform_task_budget: Arc<PlatformTaskBudget>,
    platform_tasks: CoalescedInbox<PendingPlatformTask>,
    ready_frames: Mutex<VecDeque<ReadyOutputFrame>>,
    frame_ready_wakeup: CoalescedWakeup,
    queue_overflow_wakeup: CoalescedWakeup,
    pub(in crate::flutter_runtime) render_audit: Option<Mutex<RenderDamageAudit>>,
    gpu_timing: Option<Mutex<GpuTimingState>>,
    events: Sender<RuntimeEvent>,
    generation: u64,
    desktop_size: PixelSize,
    producer: ProducerArbiter,
}

impl FlutterGlHandler {
    #[allow(clippy::too_many_arguments)]
    pub(in crate::flutter_runtime) fn new<'a>(
        render_context: egl_context::SharedEglContext,
        resource_context: egl_context::SharedEglContext,
        output_pools: impl IntoIterator<Item = OutputRenderTargetPool<'a>>,
        desktop_size: PixelSize,
        renderer_backend: RendererBackend,
        offscreen_blit: bool,
        events: Sender<RuntimeEvent>,
        generation: u64,
    ) -> Result<Arc<Self>, Box<dyn Error>> {
        let display = render_context.display().get_display_handle();
        // SAFETY: this context was just created and has never been current on
        // another thread. It is unbound before ownership reaches Flutter.
        unsafe { render_context.make_current()? };
        let gl = GlApi::load()?;
        let render_audit_active = render_audit_enabled();
        let gpu_timing = render_audit_active.then(GpuTimingState::load).flatten();
        let needs_depth_stencil = renderer_backend == RendererBackend::ImpellerGles;
        let mut depth_stencils = Vec::new();
        info!(
            %renderer_backend,
            offscreen_blit,
            "creating Flutter physical-output texture targets"
        );
        let mut targets = Vec::new();
        let mut broker_descriptors = Vec::new();

        for pool in output_pools {
            let width =
                i32::try_from(pool.size.width).map_err(|_| "Flutter output width exceeds GLES")?;
            let height = i32::try_from(pool.size.height)
                .map_err(|_| "Flutter output height exceeds GLES")?;
            let mut depth_stencil = 0;
            if needs_depth_stencil {
                // Impeller wraps Denial's supplied FBO. One packed attachment can
                // be shared by one output's rotating FBOs because the raster
                // runner is serial and clears it for each render pass.
                // SAFETY: this new GLES context is current and the arguments and
                // output pointer are valid.
                unsafe {
                    let _ = (gl.get_error)();
                    (gl.gen_renderbuffers)(1, &mut depth_stencil);
                    (gl.bind_renderbuffer)(gl::RENDERBUFFER, depth_stencil);
                    (gl.renderbuffer_storage)(
                        gl::RENDERBUFFER,
                        gl::DEPTH24_STENCIL8,
                        width,
                        height,
                    );
                }
                // SAFETY: the same GLES context remains current.
                let allocation_error = unsafe { (gl.get_error)() };
                depth_stencils.push(depth_stencil);
                if depth_stencil == 0 || allocation_error != gl::NO_ERROR {
                    warn!(
                        renderbuffer = depth_stencil,
                        error = format_args!("{allocation_error:#x}"),
                        "Impeller GLES depth/stencil allocation failed"
                    );
                    destroy_depth_stencils(gl, &mut depth_stencils);
                    destroy_targets(gl, &display, &mut targets);
                    render_context.unbind()?;
                    return Err("could not allocate Impeller GLES depth/stencil storage".into());
                }
            }

            let target_start = targets.len();
            for (buffer_index, (scanout_dmabuf, render_dmabuf)) in
                pool.dmabufs.into_iter().enumerate()
            {
                let image = match render_context
                    .display()
                    .create_image_from_dmabuf(scanout_dmabuf)
                {
                    Ok(image) => image,
                    Err(error) => {
                        destroy_targets(gl, &display, &mut targets);
                        destroy_depth_stencils(gl, &mut depth_stencils);
                        render_context.unbind()?;
                        return Err(error.into());
                    }
                };
                let mut target = GlTarget {
                    output_id: pool.output_id,
                    render_view_id: pool.render_view_id,
                    configuration_generation: pool.configuration_generation,
                    size: pool.size,
                    buffer_index,
                    scanout_image: image as usize,
                    render_image: 0,
                    scanout_texture: 0,
                    scanout_framebuffer: 0,
                    render_texture: 0,
                    render_framebuffer: 0,
                };
                let import_error;
                // SAFETY: a compatible GLES context is current and all output
                // pointers reference live local integers.
                unsafe {
                    // Attribute a driver error to this import, not to a prior
                    // output or depth/stencil allocation.
                    let _ = (gl.get_error)();
                    (gl.gen_textures)(1, &mut target.scanout_texture);
                    (gl.bind_texture)(gl::TEXTURE_2D, target.scanout_texture);
                    (gl.tex_parameter_i)(
                        gl::TEXTURE_2D,
                        gl::TEXTURE_MIN_FILTER,
                        gl::NEAREST as i32,
                    );
                    (gl.tex_parameter_i)(
                        gl::TEXTURE_2D,
                        gl::TEXTURE_MAG_FILTER,
                        gl::NEAREST as i32,
                    );
                    (gl.tex_parameter_i)(
                        gl::TEXTURE_2D,
                        gl::TEXTURE_WRAP_S,
                        gl::CLAMP_TO_EDGE as i32,
                    );
                    (gl.tex_parameter_i)(
                        gl::TEXTURE_2D,
                        gl::TEXTURE_WRAP_T,
                        gl::CLAMP_TO_EDGE as i32,
                    );
                    (gl.image_target_texture)(gl::TEXTURE_2D, image.cast());
                    import_error = (gl.get_error)();
                    (gl.gen_framebuffers)(1, &mut target.scanout_framebuffer);
                    (gl.bind_framebuffer)(gl::FRAMEBUFFER, target.scanout_framebuffer);
                    (gl.framebuffer_texture_2d)(
                        gl::FRAMEBUFFER,
                        gl::COLOR_ATTACHMENT0,
                        gl::TEXTURE_2D,
                        target.scanout_texture,
                        0,
                    );
                    if !offscreen_blit && depth_stencil != 0 {
                        (gl.framebuffer_renderbuffer)(
                            gl::FRAMEBUFFER,
                            gl::DEPTH_STENCIL_ATTACHMENT,
                            gl::RENDERBUFFER,
                            depth_stencil,
                        );
                    }
                }
                // Direct mode exposes this imported texture to Flutter. Offscreen
                // mode keeps it only as the destination of the final native-size
                // copy, so effects and partial repaint never need to read it.
                let mut actual_samples = 0;
                let mut actual_stencil_bits = 0;
                // SAFETY: the same compatible GLES context remains current, the
                // newly created framebuffer is still bound, and the output
                // pointer references a live local integer.
                let (framebuffer_status, attachment_error) = unsafe {
                    let attachment_error = (gl.get_error)();
                    let status = (gl.check_framebuffer_status)(gl::FRAMEBUFFER);
                    (gl.get_integer_v)(gl::SAMPLES, &mut actual_samples);
                    if needs_depth_stencil {
                        (gl.get_integer_v)(gl::STENCIL_BITS, &mut actual_stencil_bits);
                    }
                    (status, attachment_error)
                };
                if target.scanout_texture == 0
                    || target.scanout_framebuffer == 0
                    || import_error != gl::NO_ERROR
                    || attachment_error != gl::NO_ERROR
                    || framebuffer_status != gl::FRAMEBUFFER_COMPLETE
                    || (!offscreen_blit && actual_samples > 1)
                    || (!offscreen_blit && needs_depth_stencil && actual_stencil_bits < 8)
                {
                    warn!(
                        output = ?pool.output_id,
                        buffer_index,
                        width,
                        height,
                        format = ?scanout_dmabuf.format(),
                        import_error = format_args!("{import_error:#x}"),
                        attachment_error = format_args!("{attachment_error:#x}"),
                        texture = target.scanout_texture,
                        framebuffer = target.scanout_framebuffer,
                        status = framebuffer_status,
                        actual_samples,
                        actual_stencil_bits,
                        "Flutter output scanout FBO creation failed"
                    );
                    let mut failed = vec![target];
                    destroy_targets(gl, &display, &mut failed);
                    destroy_targets(gl, &display, &mut targets);
                    destroy_depth_stencils(gl, &mut depth_stencils);
                    render_context.unbind()?;
                    return Err(format!(
                        "Flutter output {:?} buffer {buffer_index} ({width}x{height}, {:?}) scanout framebuffer failed: status={framebuffer_status:#x}, import_error={import_error:#x}, attachment_error={attachment_error:#x}",
                        pool.output_id, scanout_dmabuf.format(),
                    ).into());
                }

                if offscreen_blit {
                    let Some(render_dmabuf) = render_dmabuf else {
                        let mut failed = vec![target];
                        destroy_targets(gl, &display, &mut failed);
                        destroy_targets(gl, &display, &mut targets);
                        destroy_depth_stencils(gl, &mut depth_stencils);
                        render_context.unbind()?;
                        return Err(
                            "offscreen blit target is missing its linear render DMA-BUF".into()
                        );
                    };
                    let render_format = AllocatorBuffer::format(render_dmabuf);
                    if render_format.code != Fourcc::Xrgb8888
                        || render_format.modifier != Modifier::Linear
                    {
                        let mut failed = vec![target];
                        destroy_targets(gl, &display, &mut failed);
                        destroy_targets(gl, &display, &mut targets);
                        destroy_depth_stencils(gl, &mut depth_stencils);
                        render_context.unbind()?;
                        return Err(format!(
                            "offscreen Flutter render target is not linear XR24: {render_format:?}"
                        )
                        .into());
                    }
                    let render_image = match render_context
                        .display()
                        .create_image_from_dmabuf(render_dmabuf)
                    {
                        Ok(image) => image,
                        Err(error) => {
                            let mut failed = vec![target];
                            destroy_targets(gl, &display, &mut failed);
                            destroy_targets(gl, &display, &mut targets);
                            destroy_depth_stencils(gl, &mut depth_stencils);
                            render_context.unbind()?;
                            return Err(error.into());
                        }
                    };
                    target.render_image = render_image as usize;
                    // Flutter's root target is an explicitly LINEAR GBM DMA-BUF.
                    // Backdrop reads therefore cannot inherit UBWC compression
                    // from either Mesa's ordinary texture allocator or scanout.
                    // SAFETY: the compatible GLES context remains current and all
                    // names and attachment dimensions belong to this handler.
                    unsafe {
                        let _ = (gl.get_error)();
                        (gl.gen_textures)(1, &mut target.render_texture);
                        (gl.bind_texture)(gl::TEXTURE_2D, target.render_texture);
                        (gl.tex_parameter_i)(
                            gl::TEXTURE_2D,
                            gl::TEXTURE_MIN_FILTER,
                            gl::NEAREST as i32,
                        );
                        (gl.tex_parameter_i)(
                            gl::TEXTURE_2D,
                            gl::TEXTURE_MAG_FILTER,
                            gl::NEAREST as i32,
                        );
                        (gl.tex_parameter_i)(
                            gl::TEXTURE_2D,
                            gl::TEXTURE_WRAP_S,
                            gl::CLAMP_TO_EDGE as i32,
                        );
                        (gl.tex_parameter_i)(
                            gl::TEXTURE_2D,
                            gl::TEXTURE_WRAP_T,
                            gl::CLAMP_TO_EDGE as i32,
                        );
                        (gl.image_target_texture)(gl::TEXTURE_2D, render_image.cast());
                        (gl.gen_framebuffers)(1, &mut target.render_framebuffer);
                        (gl.bind_framebuffer)(gl::FRAMEBUFFER, target.render_framebuffer);
                        (gl.framebuffer_texture_2d)(
                            gl::FRAMEBUFFER,
                            gl::COLOR_ATTACHMENT0,
                            gl::TEXTURE_2D,
                            target.render_texture,
                            0,
                        );
                        if depth_stencil != 0 {
                            (gl.framebuffer_renderbuffer)(
                                gl::FRAMEBUFFER,
                                gl::DEPTH_STENCIL_ATTACHMENT,
                                gl::RENDERBUFFER,
                                depth_stencil,
                            );
                        }
                    }
                    actual_samples = 0;
                    actual_stencil_bits = 0;
                    // SAFETY: the newly created render framebuffer is still bound
                    // in the current compatible GLES context.
                    let render_status = unsafe {
                        let status = (gl.check_framebuffer_status)(gl::FRAMEBUFFER);
                        (gl.get_integer_v)(gl::SAMPLES, &mut actual_samples);
                        if needs_depth_stencil {
                            (gl.get_integer_v)(gl::STENCIL_BITS, &mut actual_stencil_bits);
                        }
                        status
                    };
                    // SAFETY: querying the current context's error queue has no
                    // additional pointer or object-lifetime requirements.
                    let render_error = unsafe { (gl.get_error)() };
                    if target.render_texture == 0
                        || target.render_framebuffer == 0
                        || render_status != gl::FRAMEBUFFER_COMPLETE
                        || render_error != gl::NO_ERROR
                        || actual_samples > 1
                        || (needs_depth_stencil && actual_stencil_bits < 8)
                    {
                        warn!(
                            texture = target.render_texture,
                            framebuffer = target.render_framebuffer,
                            status = render_status,
                            error = format_args!("{render_error:#x}"),
                            actual_samples,
                            actual_stencil_bits,
                            "Flutter offscreen output FBO creation failed"
                        );
                        let mut failed = vec![target];
                        destroy_targets(gl, &display, &mut failed);
                        destroy_targets(gl, &display, &mut targets);
                        destroy_depth_stencils(gl, &mut depth_stencils);
                        render_context.unbind()?;
                        return Err("a Flutter offscreen output framebuffer is incomplete".into());
                    }
                } else {
                    target.render_framebuffer = target.scanout_framebuffer;
                }
                targets.push(target);
            }
            let framebuffers = targets[target_start..]
                .iter()
                .map(|target| target.render_framebuffer)
                .collect::<Vec<_>>();
            broker_descriptors.push((
                pool.output_id,
                pool.render_view_id,
                pool.configuration_generation,
                pool.size,
                pool.initial_scanout,
                framebuffers,
            ));
        }
        let mut shader_blit = match create_shader_blit(gl) {
            Ok(pipeline) => Some(pipeline),
            Err(error) => {
                destroy_targets(gl, &display, &mut targets);
                destroy_depth_stencils(gl, &mut depth_stencils);
                render_context.unbind()?;
                return Err(error);
            }
        };
        // SAFETY: zero is the default GLES object and the context is current.
        unsafe {
            (gl.use_program)(0);
            (gl.bind_framebuffer)(gl::FRAMEBUFFER, 0);
            (gl.bind_texture)(gl::TEXTURE_2D, 0);
            (gl.bind_renderbuffer)(gl::RENDERBUFFER, 0);
        }
        render_context.unbind()?;

        if targets.len() < 3 {
            // SAFETY: Flutter does not own this context yet.
            unsafe { render_context.make_current()? };
            destroy_shader_blit(gl, &mut shader_blit);
            destroy_targets(gl, &display, &mut targets);
            destroy_depth_stencils(gl, &mut depth_stencils);
            render_context.unbind()?;
            return Err("Flutter presentation needs physical output buffer pools".into());
        }
        let broker = match OutputBufferBroker::new(broker_descriptors.iter().map(
            |(output_id, render_view_id, configuration_generation, size, initial, framebuffers)| {
                OutputPoolDescriptor {
                    output_id: *output_id,
                    render_view_id: *render_view_id,
                    configuration_generation: *configuration_generation,
                    size: *size,
                    initial_scanout: *initial,
                    framebuffers,
                }
            },
        )) {
            Ok(broker) => broker,
            Err(error) => {
                // Keep the constructor's new validation path leak-free: GL
                // targets do not own automatic destructors.
                // SAFETY: target construction has finished, the render
                // context is unbound, and Flutter does not own it yet.
                unsafe { render_context.make_current()? };
                destroy_shader_blit(gl, &mut shader_blit);
                destroy_targets(gl, &display, &mut targets);
                destroy_depth_stencils(gl, &mut depth_stencils);
                render_context.unbind()?;
                return Err(error.into());
            }
        };
        info!(
            outputs = broker.pools.len(),
            buffers = targets.len(),
            offscreen_blit,
            render_modifier = ?offscreen_blit.then_some(Modifier::Linear),
            "imported native output pools into Flutter EGL context"
        );
        let render_audit = render_audit_active.then(|| {
            info!(
                target: "deniald::render_audit",
                width = desktop_size.width,
                height = desktop_size.height,
                gpu_timestamps = gpu_timing.is_some(),
                "Flutter physical-output render audit enabled"
            );
            Mutex::new(RenderDamageAudit::new())
        });

        Ok(Arc::new(Self {
            render_context: Mutex::new(ContextBinding::new(render_context)),
            resource_context: Mutex::new(ContextBinding::new(resource_context)),
            display,
            gl,
            targets: Mutex::new(targets),
            shader_blit: Mutex::new(shader_blit),
            depth_stencils: Mutex::new(depth_stencils),
            broker: Mutex::new(broker),
            pending_output_presentation: Mutex::new(None),
            gpu_deadline_hints: gpu_deadline::GpuDeadlineHints::default(),
            external_texture_sources: Mutex::new(HashMap::new()),
            raster_sampled_buffers: Mutex::new(Vec::new()),
            raster_sampled_feedback: Mutex::new(Vec::new()),
            sampled_buffer_release_fence: Mutex::new(None),
            sampled_buffer_batch_pool: Arc::new(Mutex::new(Vec::with_capacity(
                MAX_RECYCLED_SAMPLED_BUFFER_BATCHES,
            ))),
            dmabuf_texture_cache: Mutex::new(PartitionedRecencyCache::new(
                MAX_CACHED_DMABUF_BINDINGS_PER_TEXTURE,
            )),
            shm_texture_cache: Mutex::new(RecencyCache::new(MAX_CACHED_SHM_BINDINGS)),
            retired_external_bindings: Arc::new(RetiredExternalBindingQueue::new()),
            retired_external_binding_scratch: Mutex::new(Vec::new()),
            external_texture_lease_pool: Arc::new(Mutex::new(Vec::with_capacity(
                MAX_CACHED_EXTERNAL_TEXTURE_LEASES,
            ))),
            prepared_external_texture: Mutex::new(None),
            external_texture_resource_budget: Arc::new(ExternalTextureResourceBudget::default()),
            pending_vsync_batons: Mutex::new(PendingVsyncBatons::default()),
            platform_task_budget: Arc::new(PlatformTaskBudget::default()),
            platform_tasks: CoalescedInbox::with_capacity(INITIAL_PLATFORM_TASK_BATCH_CAPACITY),
            ready_frames: Mutex::new(VecDeque::with_capacity(8)),
            frame_ready_wakeup: CoalescedWakeup::default(),
            queue_overflow_wakeup: CoalescedWakeup::default(),
            render_audit,
            gpu_timing: gpu_timing.map(Mutex::new),
            events,
            generation,
            desktop_size,
            producer: ProducerArbiter::new(),
        }))
    }

    pub(in crate::flutter_runtime) fn take_ready_frame(
        &self,
        mut output_available: impl FnMut(OutputId) -> bool,
    ) -> Option<ReadyOutputFrame> {
        let mut frames = lock(&self.ready_frames);
        let index = frames
            .iter()
            .position(|frame| output_available(frame.output_id))?;
        frames.remove(index)
    }

    pub(in crate::flutter_runtime) fn has_ready_frames(&self) -> bool {
        !lock(&self.ready_frames).is_empty()
    }

    pub(in crate::flutter_runtime) fn publish_output(
        &self,
        output: &ReadyOutputFrame,
    ) -> Result<(), &'static str> {
        lock(&self.broker).publish(output)
    }

    pub(in crate::flutter_runtime) fn authorize_outputs(
        &self,
        requests: &[OutputFrameRequest],
        views: &mut Vec<i64>,
    ) {
        views.clear();
        let mut broker = lock(&self.broker);
        let now = Instant::now();
        for request in requests {
            if let Some(view) = broker.authorize(*request, now) {
                views.push(view);
            }
        }
    }

    pub(in crate::flutter_runtime) fn output_target_available(&self, output: OutputId) -> bool {
        lock(&self.broker).target_available(output)
    }

    pub(in crate::flutter_runtime) fn with_output_target_availability<T>(
        &self,
        now: Instant,
        action: impl FnOnce(&mut dyn FnMut(OutputId) -> bool) -> T,
    ) -> (T, usize) {
        let mut broker = lock(&self.broker);
        let expired = broker.expire_authorizations(now);
        let mut target_available = |output| broker.target_available(output);
        (action(&mut target_available), expired)
    }

    pub(in crate::flutter_runtime) fn cancel_output_authorizations(&self, render_view_ids: &[i64]) {
        lock(&self.broker).cancel_authorizations(render_view_ids);
    }

    pub(in crate::flutter_runtime) fn release_output(
        &self,
        output: OutputId,
        index: usize,
    ) -> Result<(), &'static str> {
        lock(&self.broker).release_output(output, index)
    }

    pub(in crate::flutter_runtime) fn retain_output(
        &self,
        output: OutputId,
        index: usize,
    ) -> Result<(), &'static str> {
        lock(&self.broker).retain_output(output, index)
    }

    pub(in crate::flutter_runtime) fn tag_next_frame_for_screenshot(
        &self,
        output: OutputId,
        request_id: u64,
    ) -> Result<(), &'static str> {
        lock(&self.broker).tag_next_frame_for_screenshot(output, request_id)
    }

    pub(in crate::flutter_runtime) fn cancel_screenshot_frame(&self, request_id: u64) {
        lock(&self.broker).cancel_screenshot_frame(request_id);
    }

    pub(in crate::flutter_runtime) fn set_external_texture_sources(
        &self,
        frames: impl IntoIterator<Item = ExternalTextureFrame>,
        changed: &mut Vec<i64>,
    ) {
        let mut sources = lock(&self.external_texture_sources);
        for ExternalTextureFrame {
            texture_id,
            source,
            expects_sample,
        } in frames
        {
            if sources
                .entry(texture_id)
                .or_default()
                .queue(source, expects_sample)
            {
                changed.push(texture_id);
            }
        }
    }

    pub(in crate::flutter_runtime) fn advance_external_texture_sources(
        &self,
        texture_ids: &[i64],
        deferred: &mut Vec<i64>,
    ) {
        let mut sources = lock(&self.external_texture_sources);
        for texture_id in texture_ids {
            if let Some(slot) = sources.get_mut(texture_id) {
                slot.advance();
                if slot.has_queued() {
                    deferred.push(*texture_id);
                }
            }
        }
    }

    pub(in crate::flutter_runtime) fn advance_all_external_texture_sources(
        &self,
        changed: &mut Vec<i64>,
    ) {
        let mut sources = lock(&self.external_texture_sources);
        for (texture_id, slot) in sources.iter_mut() {
            if slot.advance() {
                changed.push(*texture_id);
            }
        }
    }

    pub(in crate::flutter_runtime) fn current_external_texture(
        &self,
        texture_id: i64,
    ) -> Option<ExternalTextureSource> {
        lock(&self.external_texture_sources)
            .get(&texture_id)?
            .current
            .clone()
    }

    pub(in crate::flutter_runtime) fn mark_external_texture_sampled(
        &self,
        texture_id: i64,
        generation: u64,
    ) {
        let mut sources = lock(&self.external_texture_sources);
        let Some(slot) = sources.get_mut(&texture_id) else {
            return;
        };
        if slot
            .current
            .as_ref()
            .is_some_and(|source| source.generation() == generation)
        {
            slot.current_sampled = true;
        }
    }

    fn record_sampled_feedback(&self, feedback: Option<crate::surface_feedback::SurfaceFeedback>) {
        if let Some(feedback) = feedback.filter(|token| token.pending()) {
            let mut sampled = lock(&self.raster_sampled_feedback);
            if !sampled.iter().any(|token| token.same(&feedback)) {
                sampled.push(feedback);
            }
        }
    }

    pub(in crate::flutter_runtime) fn record_sampled_buffer(
        &self,
        texture_id: i64,
        generation: u64,
        buffer_guard: ExternalBufferGuard,
    ) {
        let mut sampled = lock(&self.raster_sampled_buffers);
        if sampled
            .iter()
            .any(|hold| hold.texture_id == texture_id && hold.generation == generation)
        {
            return;
        }
        sampled.push(SampledBufferHold {
            texture_id,
            generation,
            _buffer_guard: buffer_guard,
        });
    }

    pub(in crate::flutter_runtime) fn seal_sampled_buffers(
        &self,
    ) -> Option<SampledBufferHoldBatch> {
        let mut sampled = lock(&self.raster_sampled_buffers);
        if sampled.is_empty() {
            return None;
        }
        let mut replacement = lock(&self.sampled_buffer_batch_pool)
            .pop()
            .unwrap_or_default();
        debug_assert!(replacement.is_empty());
        mem::swap(&mut *sampled, &mut replacement);
        Some(SampledBufferHoldBatch {
            holds: Some(replacement),
            pool: Arc::downgrade(&self.sampled_buffer_batch_pool),
        })
    }

    pub(in crate::flutter_runtime) fn rearm_abandoned_samples(&self) {
        let sampled = lock(&self.raster_sampled_buffers);
        if sampled.is_empty() {
            return;
        }
        let mut sources = lock(&self.external_texture_sources);
        for hold in sampled.iter() {
            let Some(slot) = sources.get_mut(&hold.texture_id) else {
                continue;
            };
            if slot
                .current
                .as_ref()
                .is_some_and(|source| source.generation() == hold.generation)
            {
                slot.current_sampled = false;
            }
        }
    }

    pub(in crate::flutter_runtime) fn publish_sampled_buffer_release(
        &self,
        fence: Option<OwnedFd>,
        batch: Option<SampledBufferHoldBatch>,
    ) -> bool {
        let Some(batch) = batch else {
            return true;
        };
        match self
            .events
            .send(RuntimeEvent::SampledBuffersReady { fence, batch })
        {
            Ok(()) => true,
            Err(error) => {
                // The event-loop owner disappeared before it could watch the
                // sync_file. Complete the command stream before retaining the
                // orphaned event through process teardown.
                // SAFETY: this helper is called only by render-thread
                // callbacks while Flutter's GLES context is current.
                unsafe { (self.gl.finish)() };
                // The compositor receiver no longer exists, so there is no
                // sound Wayland thread on which to release these guards.
                // Preserve them through process teardown instead of running
                // wl_buffer.release from Flutter's raster thread.
                mem::forget(error);
                false
            }
        }
    }

    pub(in crate::flutter_runtime) fn remove_external_texture_source(&self, texture_id: i64) {
        lock(&self.external_texture_sources).remove(&texture_id);
        let retired_dmabufs = lock(&self.dmabuf_texture_cache).remove(&texture_id);
        let retired_shm =
            lock(&self.shm_texture_cache).remove_where(|(owner, _)| *owner == texture_id);
        // Dropping a cache reference never issues GL calls. If no Flutter
        // lease still references the binding, its Drop queues destruction for
        // the next callback with the raster context current.
        drop((retired_dmabufs, retired_shm));
    }

    pub(in crate::flutter_runtime) fn cached_dmabuf_binding(
        &self,
        texture_id: i64,
        dmabuf: &Dmabuf,
    ) -> Option<Arc<CachedTextureBinding>> {
        lock(&self.dmabuf_texture_cache).get_by(&texture_id, |cached| cached == dmabuf)
    }

    pub(in crate::flutter_runtime) fn cache_dmabuf_binding(
        &self,
        texture_id: i64,
        dmabuf: Dmabuf,
        binding: Arc<CachedTextureBinding>,
    ) {
        let retired = lock(&self.dmabuf_texture_cache).insert(texture_id, dmabuf, binding);
        drop(retired);
    }

    pub(in crate::flutter_runtime) fn cached_shm_binding(
        &self,
        texture_id: i64,
        revision: u64,
    ) -> Option<Arc<CachedTextureBinding>> {
        lock(&self.shm_texture_cache)
            .get_by(|(owner, cached_revision)| *owner == texture_id && *cached_revision == revision)
    }

    pub(in crate::flutter_runtime) fn cache_shm_binding(
        &self,
        texture_id: i64,
        revision: u64,
        binding: Arc<CachedTextureBinding>,
    ) {
        let retired = lock(&self.shm_texture_cache).insert((texture_id, revision), binding);
        drop(retired);
    }

    pub(in crate::flutter_runtime) fn lease_external_texture(
        &self,
        resource: ExternalTextureLeaseResource,
    ) -> Box<ExternalTextureLease> {
        let mut lease = lock(&self.external_texture_lease_pool)
            .pop()
            .unwrap_or_else(|| {
                Box::new(ExternalTextureLease {
                    resource: None,
                    pool: Arc::downgrade(&self.external_texture_lease_pool),
                })
            });
        debug_assert!(lease.resource.is_none());
        lease.resource = Some(resource);
        lease
    }

    pub(in crate::flutter_runtime) fn complete_vsync(&self, baton: isize) {
        lock(&self.pending_vsync_batons).complete(baton);
    }

    pub(in crate::flutter_runtime) fn take_pending_vsync_batons(&self) -> VecDeque<isize> {
        lock(&self.pending_vsync_batons).take_all()
    }

    pub(in crate::flutter_runtime) fn take_next_vsync(&self) -> (Option<isize>, bool) {
        let mut pending = lock(&self.pending_vsync_batons);
        let baton = pending.take_next();
        (baton, pending.has_pending())
    }

    pub(in crate::flutter_runtime) fn restore_vsync(&self, baton: isize) {
        lock(&self.pending_vsync_batons).restore_front(baton);
    }

    pub(in crate::flutter_runtime) fn has_pending_vsync(&self) -> bool {
        lock(&self.pending_vsync_batons).has_pending()
    }

    pub(in crate::flutter_runtime) fn try_request_frame(&self) -> bool {
        self.producer.try_request(Instant::now())
    }

    pub(in crate::flutter_runtime) fn cancel_requested_frame(&self) {
        self.producer.cancel_request();
    }

    pub(in crate::flutter_runtime) fn begin_raster_frame(&self) -> bool {
        self.producer.begin_raster()
    }

    pub(in crate::flutter_runtime) fn begin_present(&self) {
        self.producer.begin_present();
    }

    pub(in crate::flutter_runtime) fn finish_producer_frame(&self) -> FlutterProducerState {
        self.producer.finish()
    }

    pub(in crate::flutter_runtime) fn acknowledge_frame_ready(&self) {
        self.frame_ready_wakeup.acknowledge();
    }

    pub(in crate::flutter_runtime) fn publish_ready_frames(
        &self,
        frames: Vec<ReadyOutputFrame>,
    ) -> bool {
        if frames.is_empty() {
            return true;
        }
        lock(&self.ready_frames).extend(frames);
        if !self.frame_ready_wakeup.begin() {
            return true;
        }
        let sent = self
            .events
            .send(RuntimeEvent::FrameReady {
                generation: self.generation,
            })
            .is_ok();
        if !sent {
            self.frame_ready_wakeup.acknowledge();
        }
        sent
    }

    pub(in crate::flutter_runtime) fn take_platform_tasks(
        &self,
        output: &mut Vec<PendingPlatformTask>,
    ) {
        self.platform_tasks.take_into(output);
    }

    pub(in crate::flutter_runtime) fn report_queue_overflow(&self, queue: &'static str) {
        if !self.queue_overflow_wakeup.begin() {
            return;
        }
        if self
            .events
            .send(RuntimeEvent::QueueOverflow {
                generation: self.generation,
                queue,
            })
            .is_err()
        {
            self.queue_overflow_wakeup.acknowledge();
        }
    }

    pub(in crate::flutter_runtime) fn blit_to_scanout(&self, render_framebuffer: u32) -> bool {
        let target = lock(&self.targets)
            .iter()
            .find(|target| target.render_framebuffer == render_framebuffer)
            .copied();
        let Some(target) = target else {
            error!(
                framebuffer = render_framebuffer,
                "Flutter presented an unknown physical-output target"
            );
            return false;
        };
        if !target.needs_blit() {
            return true;
        }

        let Some(shader_blit) = *lock(&self.shader_blit) else {
            error!("offscreen Flutter target has no shader-copy pipeline");
            return false;
        };

        if let Err(error) = copy_to_scanout(
            self.gl,
            target.render_texture,
            target.scanout_framebuffer,
            target.size,
            shader_blit,
        ) {
            error!(
                framebuffer = render_framebuffer,
                scanout_framebuffer = target.scanout_framebuffer,
                error = format_args!("{error:#x}"),
                "Flutter scene-to-scanout shader copy failed"
            );
            return false;
        }
        true
    }

    /// Destroys every context-bound GL object owned by this handler. Returns
    /// false when the render context or a teardown mutex stayed owned by a
    /// surviving engine worker — the untouched objects are then retained for
    /// the process to outlive. The clean-shutdown path always observes true:
    /// EngineHost has already joined the raster thread, so nothing is
    /// contended and the context is not current anywhere else.
    pub(in crate::flutter_runtime) fn destroy_targets(&self) -> bool {
        // These guards stay held across eglMakeCurrent and the GL deletes
        // below, so teardown must not queue behind a surviving worker's
        // critical section: contention retains the objects for the process
        // instead of blocking. The clean-shutdown path never observes
        // contention — the raster thread is joined before this runs.
        let (Some(mut targets), Some(mut shader_blit), Some(mut depth_stencils)) = (
            try_lock(&self.targets),
            try_lock(&self.shader_blit),
            try_lock(&self.depth_stencils),
        ) else {
            return false;
        };
        if targets.is_empty()
            && shader_blit.is_none()
            && depth_stencils.is_empty()
            && !self
                .retired_external_bindings
                .pending
                .load(Ordering::Relaxed)
        {
            return true;
        }
        // The cache mutexes below are only ever held across bounded CPU
        // work, so they can be taken normally; the render-context mutex is
        // the one a worker may hold across a wedged driver call.
        let Some(mut context) = try_lock(&self.render_context) else {
            error!("a surviving engine worker still owns the Flutter render context");
            return false;
        };
        // SAFETY: on the clean path the raster thread is joined and the
        // context is not current anywhere else. After a failed shutdown a
        // surviving worker may still hold it current; eglMakeCurrent then
        // fails and every GL object is retained for the process to outlive.
        if let Err(error) = unsafe { context.context.make_current() } {
            error!(%error, "could not bind Flutter context for output-target cleanup");
            return false;
        }
        context.owner = Some(thread::current().id());
        let cached_dmabufs = lock(&self.dmabuf_texture_cache).drain();
        let cached_shm = lock(&self.shm_texture_cache).drain();
        drop((cached_dmabufs, cached_shm));
        let retired_done = self.destroy_retired_external_bindings();
        if let Some(gpu_timing) = &self.gpu_timing
            && let Some(mut gpu_timing) = try_lock(gpu_timing)
        {
            gpu_timing.clear();
        }
        destroy_shader_blit(self.gl, &mut shader_blit);
        destroy_targets(self.gl, &self.display, &mut targets);
        destroy_depth_stencils(self.gl, &mut depth_stencils);
        let _ = context.clear_current();
        retired_done
    }

    /// Drains the retired queue while the render context is current. Returns
    /// false when a callback thread still holds the scratch or queue lock —
    /// the pending flag then stays set so a later call retries — which keeps
    /// the failed-shutdown teardown from hanging behind a wedged worker.
    pub(in crate::flutter_runtime) fn destroy_retired_external_bindings(&self) -> bool {
        // The flag is a hint in front of the mutex-protected queue. Missing a
        // concurrent transition here only defers reclamation to the next
        // callback; it cannot lose the queued binding or clear the flag.
        if !self
            .retired_external_bindings
            .pending
            .load(Ordering::Relaxed)
        {
            return true;
        }
        let Some(mut retired) = try_lock(&self.retired_external_binding_scratch) else {
            return false;
        };
        {
            let Some(mut pending) = try_lock(&self.retired_external_bindings.bindings) else {
                return false;
            };
            // Binding drops always set the flag after pushing, so clearing it
            // while holding the queue cannot lose a concurrent retirement.
            self.retired_external_bindings
                .pending
                .store(false, Ordering::Relaxed);
            debug_assert!(retired.is_empty());
            mem::swap(&mut *retired, &mut *pending);
        }
        for binding in retired.drain(..) {
            // SAFETY: this is called only with the Flutter render context
            // current, and every object was created by that context.
            unsafe {
                if binding.texture != 0 {
                    (self.gl.delete_textures)(1, &binding.texture);
                }
                if let Some((_dmabuf, image)) = binding.dmabuf_image
                    && image != 0
                {
                    egl_ffi::egl::DestroyImageKHR(
                        self.display.handle,
                        image as egl_ffi::egl::types::EGLImageKHR,
                    );
                }
            }
        }
        true
    }

    /// Reclaims handler resources after `EngineHost::shutdown` failed and
    /// reports what could not be released.
    ///
    /// A failed FlutterEngineShutdown gives no guarantee that engine workers
    /// stopped, so two ordering rules apply. Every release below is either
    /// engine-independent state this thread may always drop — sources are
    /// cleared first so a surviving worker cannot mint new EGLImage/texture
    /// bindings — or the same context-bound teardown as the clean path, which
    /// never blocks on a lock a worker could hold across a wedged driver
    /// call. `eglMakeCurrent` itself fails when a worker still holds the
    /// render context, which retains the whole GPU object set for the
    /// process to outlive.
    pub(in crate::flutter_runtime) fn destroy_targets_after_engine_failure(
        &self,
    ) -> EngineFailureTeardown {
        let mut report = EngineFailureTeardown::default();
        // Move every engine-independent collection out of its mutex first:
        // dropping these values runs Wayland buffer release, DRM syncobj
        // signal, presentation-discard and fd-close side effects, which are
        // not bounded CPU work and must not execute under the guard.
        let sources = mem::take(&mut *lock(&self.external_texture_sources));
        report.released_sources = sources.len();
        let sampled = mem::take(&mut *lock(&self.raster_sampled_buffers));
        report.released_sampled_buffers = sampled.len();
        let feedback = mem::take(&mut *lock(&self.raster_sampled_feedback));
        let prepared = lock(&self.prepared_external_texture).take();
        let release_fence = lock(&self.sampled_buffer_release_fence).take();
        // Pooled leases are retired tokens whose resource was already
        // released by ExternalTextureLease::retire, so dropping them frees
        // only boxes. Pooled hold batches are recycled Vec capacity that can
        // still carry holds. Neither mutex is ever held across a driver
        // call, so taking them cannot wedge on a stuck worker.
        let lease_tokens = mem::take(&mut *lock(&self.external_texture_lease_pool));
        report.released_lease_tokens = lease_tokens.len();
        let batch_pool = mem::take(&mut *lock(&self.sampled_buffer_batch_pool));
        drop((
            sources,
            sampled,
            feedback,
            prepared,
            release_fence,
            lease_tokens,
            batch_pool,
        ));
        // Cache drops only queue their bindings for context-bound
        // destruction; drain them here so the queued count is measured even
        // when the render context stays owned by a surviving worker.
        let cached_dmabufs = lock(&self.dmabuf_texture_cache).drain();
        let cached_shm = lock(&self.shm_texture_cache).drain();
        report.queued_cached_bindings = cached_dmabufs.len().saturating_add(cached_shm.len());
        drop((cached_dmabufs, cached_shm));
        report.gl_teardown_completed = self.destroy_targets();
        self.measure_retained(&mut report);
        report
    }

    /// Counts the GL resources still owned by this handler after a teardown
    /// attempt. The retired-queue and target mutexes are only held across
    /// bounded CPU work, so blocking here cannot wedge on a stuck driver.
    fn measure_retained(&self, report: &mut EngineFailureTeardown) {
        // Nominal driver-side bookkeeping per GL container object (FBO,
        // renderbuffer, program); pixel storage dominates the estimate.
        const GL_CONTAINER_OBJECT_BYTES: usize = 4 * 1024;
        let desktop_plane = (self.desktop_size.width as usize)
            .saturating_mul(self.desktop_size.height as usize)
            .saturating_mul(4);
        let mut estimated_bytes = 0usize;
        let mut largest_output_plane = 0usize;
        {
            let targets = lock(&self.targets);
            for target in targets.iter() {
                let plane = (target.size.width as usize)
                    .saturating_mul(target.size.height as usize)
                    .saturating_mul(4);
                largest_output_plane = largest_output_plane.max(plane);
                // One texture plane per target, plus the separate render
                // plane when the offscreen blit owns a second texture, plus
                // the framebuffer's driver-side bookkeeping.
                let planes = if target.needs_blit() { 2 } else { 1 };
                estimated_bytes = estimated_bytes
                    .saturating_add(plane.saturating_mul(planes))
                    .saturating_add(GL_CONTAINER_OBJECT_BYTES);
            }
            report.retained_targets = targets.len();
        }
        // One packed depth/stencil renderbuffer exists per output pool, sized
        // to that output's current mode. There is no per-stencil size record,
        // so the largest live output plane is the closest bound; the desktop
        // plane stands in when no target survived to measure.
        let stencil_plane = if largest_output_plane == 0 {
            desktop_plane
        } else {
            largest_output_plane
        };
        report.retained_depth_stencils = lock(&self.depth_stencils).len();
        estimated_bytes = estimated_bytes.saturating_add(
            report
                .retained_depth_stencils
                .saturating_mul(stencil_plane.saturating_add(GL_CONTAINER_OBJECT_BYTES)),
        );
        report.retained_shader_blit = lock(&self.shader_blit).is_some();
        if report.retained_shader_blit {
            estimated_bytes = estimated_bytes.saturating_add(GL_CONTAINER_OBJECT_BYTES);
        }
        {
            let retired = lock(&self.retired_external_bindings.bindings);
            for binding in retired.iter() {
                let binding_bytes = match &binding.dmabuf_image {
                    Some((dmabuf, _)) => {
                        // u64 keeps the multiply lossless; a conversion that
                        // ever failed saturates loudly instead of recording
                        // a silent zero.
                        let plane = u64::from(dmabuf.width())
                            .saturating_mul(u64::from(dmabuf.height()))
                            .saturating_mul(4);
                        usize::try_from(plane).unwrap_or(usize::MAX)
                    }
                    // SHM bindings keep no size record; the desktop plane is
                    // the closest bound for a surface-sized texture.
                    None => desktop_plane,
                };
                estimated_bytes = estimated_bytes.saturating_add(binding_bytes);
            }
            report.retained_external_bindings = retired.len();
        }
        // One resource permit is held by every ExternalTextureBinding and by
        // every lease handed to Flutter as user_data. After the drains above
        // moved cached bindings into the retired queue and released the
        // prepared texture, live-minus-retired is an upper bound on leases a
        // failed shutdown leaves outstanding: their destruction_callback may
        // still arrive from a surviving worker, so they leak by contract but
        // are metered here at one surface-sized plane plus its objects.
        let outstanding_permits = self
            .external_texture_resource_budget
            .live
            .load(Ordering::Relaxed);
        report.inflight_external_leases =
            outstanding_permits.saturating_sub(report.retained_external_bindings);
        estimated_bytes = estimated_bytes.saturating_add(
            report
                .inflight_external_leases
                .saturating_mul(desktop_plane.saturating_add(GL_CONTAINER_OBJECT_BYTES)),
        );
        report.retained_estimated_bytes = estimated_bytes;
    }

    /// Reserves a cache hit for the immediately following Flutter texture
    /// callback without issuing GL calls. Holding the binding and Wayland
    /// guard here closes the race between the engine's preflight and callback.
    pub(in crate::flutter_runtime) fn prepare_external_texture_without_gl(
        &self,
        texture_id: i64,
    ) -> bool {
        let mut prepared_slot = lock(&self.prepared_external_texture);
        if prepared_slot.take().is_some() {
            return false;
        }
        if self
            .retired_external_bindings
            .pending
            .load(Ordering::Relaxed)
        {
            return false;
        }
        let Some(source) = self.current_external_texture(texture_id) else {
            return false;
        };
        let source_generation = source.generation();
        let feedback = source.feedback();
        let Some(lease_permit) = self.external_texture_resource_budget.try_acquire() else {
            return false;
        };
        let (width, height, binding, resource, sampled_buffer) = match source {
            ExternalTextureSource::Dmabuf {
                dmabuf,
                buffer_guard,
                revision: _,
                feedback: _,
            } => {
                let dmabuf_width = dmabuf.width();
                let dmabuf_height = dmabuf.height();
                let width = usize::try_from(dmabuf_width).unwrap_or_default();
                let height = usize::try_from(dmabuf_height).unwrap_or_default();
                let Some(binding) = self.cached_dmabuf_binding(texture_id, &dmabuf) else {
                    return false;
                };
                let sampled_buffer = buffer_guard.clone();
                let resource = ExternalTextureLeaseResource::Dmabuf {
                    _binding: Arc::clone(&binding),
                    _buffer_guard: buffer_guard,
                    _resource_permit: lease_permit,
                };
                (width, height, binding, resource, sampled_buffer)
            }
            ExternalTextureSource::Shm(frame) => {
                let width = usize::try_from(frame.width).unwrap_or_default();
                let height = usize::try_from(frame.height).unwrap_or_default();
                let Some(binding) = self.cached_shm_binding(texture_id, frame.revision) else {
                    return false;
                };
                let resource = ExternalTextureLeaseResource::Shm {
                    _binding: Arc::clone(&binding),
                    _resource_permit: lease_permit,
                };
                (width, height, binding, resource, None)
            }
        };
        let name = binding.texture();
        if width == 0 || height == 0 || name == 0 {
            return false;
        }
        *prepared_slot = Some(PreparedExternalTexture {
            texture_id,
            source_generation,
            feedback,
            width,
            height,
            name,
            resource,
            sampled_buffer,
        });
        true
    }

    /// Drain the bounded GLES error queue while the Flutter render context is
    /// current. Returning the first error lets callers reject a partially
    /// created texture without caching or publishing it to Flutter.
    pub(in crate::flutter_runtime) fn take_gl_error(&self) -> Option<u32> {
        const GL_NO_ERROR: u32 = 0;
        const MAX_DRAINED_ERRORS: usize = 16;

        let mut first = None;
        for _ in 0..MAX_DRAINED_ERRORS {
            // SAFETY: every caller runs from a Flutter callback with this
            // handler's render context current.
            let error = unsafe { (self.gl.get_error)() };
            if error == GL_NO_ERROR {
                break;
            }
            first.get_or_insert(error);
        }
        first
    }
}

/// Lock-poisoning-tolerant try_lock used by the failed-shutdown path, where
/// a contended mutex means a surviving engine worker still owns it. Poison
/// is reported once per recovery so a panicking worker is not silent.
fn try_lock<T>(mutex: &Mutex<T>) -> Option<MutexGuard<'_, T>> {
    match mutex.try_lock() {
        Ok(guard) => Some(guard),
        Err(std::sync::TryLockError::Poisoned(poisoned)) => {
            warn!("recovering a poisoned Flutter renderer lock during teardown");
            Some(poisoned.into_inner())
        }
        Err(std::sync::TryLockError::WouldBlock) => None,
    }
}

pub(in crate::flutter_runtime) fn vm_service_uri_from_log(message: &str) -> Option<&str> {
    const MAX_VM_SERVICE_URI_BYTES: usize = 2048;
    const ANNOUNCEMENT: &str = "The Dart VM service is listening on ";
    const LOOPBACK_PREFIX: &str = "http://127.0.0.1:";
    let start = message
        .find(ANNOUNCEMENT)?
        .checked_add(ANNOUNCEMENT.len())?;
    let uri = message[start..]
        .split_ascii_whitespace()
        .next()?
        .trim_end_matches(['.', ',', ';']);
    if uri.len() > MAX_VM_SERVICE_URI_BYTES {
        return None;
    }
    let authority_and_path = uri.strip_prefix(LOOPBACK_PREFIX)?;
    let (port, authentication_path) = authority_and_path.split_once('/')?;
    if port.parse::<u16>().ok().is_none_or(|port| port == 0)
        || authentication_path.is_empty()
        || !authentication_path
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'/' | b'=' | b'_' | b'-'))
    {
        return None;
    }
    Some(uri)
}
