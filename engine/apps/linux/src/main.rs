//! 服务进程入口：读配置、装配 Engine、连宿主的 `ime.sock` 服务到进程结束。
//! 逻辑在库部分（`qingjian_linux`），这里只做装配与启动；断线重连由
//! `ime::Service` 自己管。

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::Parser;
use qingjian_core::{Engine, Language};
use qingjian_linux::assembly::{self, AssemblySpec, LanguageModelFiles};
use qingjian_linux::ime::{Service, socket_path};
use qingjian_linux::session::{self, Session, SessionConfig};
use qingjian_linux::{LinuxError, config};
use qingjian_platform::{Config, LogLevel};

/// 青简 Linux 输入引擎服务：作为 input-engine-v1 客户端连宿主合成器的
/// `$XDG_RUNTIME_DIR/denial/ime.sock`。
#[derive(Parser)]
#[command(version, about)]
struct Args {
    /// 宿主 socket 路径；缺省 `$XDG_RUNTIME_DIR/denial/ime.sock`。
    #[arg(long, env = "QINGJIAN_IME_SOCKET")]
    socket: Option<PathBuf>,

    /// 主词库路径（`.qj` 或 TSV）；缺省随包词库，再没有回落手写样例。
    #[arg(long, env = "QINGJIAN_DICT")]
    dict: Option<PathBuf>,

    /// 随包数据根目录（含 `data/`、`assets/`）。
    #[arg(long, env = "QINGJIAN_DATA_DIR")]
    data_dir: Option<PathBuf>,
}

/// 读密钥：工作目录 `.env`，再叠加配置目录的 `.env`；不覆盖已有环境变量。
fn load_env() {
    let _ = dotenvy::dotenv();
    if let Some(dir) = config::config_file().parent() {
        let _ = dotenvy::from_path(dir.join(".env"));
    }
}

fn learning_language(config: &Config) -> Language {
    let code = &config.general.learning_language;
    code.parse().unwrap_or_else(|_| {
        tracing::warn!(code, "不认识的学习语言，按英文");
        Language::English
    })
}

/// `<root>/data/generated/<name>`，不存在为 `None`。
fn generated(root: &Path, name: &str) -> Option<PathBuf> {
    existing(root.join("data/generated").join(name))
}

/// `<root>/assets/<rel>`，不存在为 `None`。
fn asset(root: &Path, rel: &str) -> Option<PathBuf> {
    existing(root.join("assets").join(rel))
}

fn existing(path: PathBuf) -> Option<PathBuf> {
    path.is_file().then_some(path)
}

/// 正式词库，没有就回落手写样例。
fn default_dict(root: &Path) -> PathBuf {
    generated(root, "dict.qj").unwrap_or_else(|| sample_dict(root))
}

fn sample_dict(root: &Path) -> PathBuf {
    root.join("assets/sample/dict.tsv")
}

/// 某语言的释义表：打包过的优先，否则随 git 的 TSV。
fn glossary_file(root: &Path, language: Language) -> Option<PathBuf> {
    let code = language.code();
    generated(root, &format!("glossary-{code}.qj"))
        .or_else(|| asset(root, &format!("glossary/glossary-{code}.tsv")))
}

/// 正式词库装配失败回落样例词库，连样例都装不起来才报错。
fn assemble_with_fallback(mut spec: AssemblySpec, root: &Path) -> Result<Engine, LinuxError> {
    assembly::assemble(&spec).or_else(|error| {
        tracing::error!(%error, dict = %spec.dict.display(), "正式词库装配失败，回落样例词库");
        spec.dict = sample_dict(root);
        assembly::assemble(&spec)
    })
}

/// 本地整句模型文件：`QINGJIAN_MODEL_DIR` > 用户目录 `model/` > 随包 `data/model/`。
fn find_model(user_dir: &Path, root: &Path) -> Option<PathBuf> {
    [
        std::env::var_os("QINGJIAN_MODEL_DIR").map(PathBuf::from),
        Some(user_dir.join("model")),
        Some(root.join("data/model")),
    ]
    .into_iter()
    .flatten()
    .find_map(|dir| qingjian_neural::find_model(&dir))
}

/// 级别按 `[general] log_level`（`RUST_LOG` 可覆盖），同时写 stderr 与按天滚动的
/// 文件（`$XDG_STATE_HOME/qingjian/logs`，留 7 天）。guard 要活到进程结束。
fn init_logging(config: &Config) -> Option<tracing_appender::non_blocking::WorkerGuard> {
    use tracing_subscriber::fmt::writer::MakeWriterExt;
    let level = if config.general.log_level == LogLevel::Debug {
        "debug"
    } else {
        "info"
    };
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(level));
    let dir = config::log_dir();
    if std::fs::create_dir_all(&dir).is_err() {
        tracing_subscriber::fmt().with_env_filter(filter).init();
        return None;
    }
    match tracing_appender::rolling::RollingFileAppender::builder()
        .rotation(tracing_appender::rolling::Rotation::DAILY)
        .filename_prefix("qingjian-linux")
        .filename_suffix("log")
        .max_log_files(7)
        .build(&dir)
    {
        Ok(appender) => {
            let (writer, guard) = tracing_appender::non_blocking(appender);
            tracing_subscriber::fmt()
                .with_env_filter(filter)
                .with_ansi(false)
                .with_writer(writer.and(std::io::stderr))
                .init();
            Some(guard)
        }
        Err(_) => {
            tracing_subscriber::fmt().with_env_filter(filter).init();
            None
        }
    }
}

/// 退出码走 `ExitCode` 返回而不是 `std::process::exit`：后者跳过局部
/// Drop，`tracing_appender` 的 non-blocking guard 不落地，最后一条
/// 错误日志可能丢。
fn main() -> ExitCode {
    let args = Args::parse();
    load_env();
    // 日志级别取自配置，所以先读配置再装日志；配置读不了退回默认值继续跑。
    let (config, config_path) = match config::load_config() {
        Ok(pair) => pair,
        Err(error) => {
            eprintln!("{error}");
            (Config::default(), config::config_file())
        }
    };
    let _log_guard = init_logging(&config);
    let language = learning_language(&config);
    let root = args.data_dir.clone().unwrap_or_else(config::bundled_root);
    let dict = args.dict.clone().unwrap_or_else(|| default_dict(&root));
    let glossary = glossary_file(&root, language).filter(|path| path.is_file());
    let bundled_dicts_dir = Some(root.join("data/generated/dicts")).filter(|dir| dir.is_dir());
    let user_dir = config::user_dir();
    let spec = AssemblySpec {
        glossary: glossary.clone().map(|path| (language, path)),
        english_glossary: glossary_file(&root, Language::Chinese),
        english: generated(&root, "english.tsv"),
        emoji: ["emoji-zh.tsv", "emoji-en.tsv"]
            .into_iter()
            .filter_map(|name| asset(&root, &format!("emoji/{name}")))
            .collect(),
        language_model: LanguageModelFiles::find(&root.join("data/generated")),
        bundled_dicts_dir: bundled_dicts_dir.clone(),
        dictionaries: config.dictionaries.clone(),
        levels_dir: Some(root.join("assets/levels")),
        user_dir: Some(user_dir.clone()),
        input_log: config.general.input_log,
        ..AssemblySpec::new(&dict)
    };
    let mut engine = match assemble_with_fallback(spec, &root) {
        Ok(engine) => engine,
        Err(error) => {
            tracing::error!(%error, "样例词库也装配失败");
            return ExitCode::FAILURE;
        }
    };
    engine.set_fuzzy(config.fuzzy);
    engine.set_shuangpin(config.general.shuangpin());
    engine.set_zhuyin_mode(config.general.zhuyin);
    engine.set_mode_keys(config.shortcut.mode);
    engine.set_full_width_punctuation(config.general.full_width_punctuation);
    if let Err(error) = engine.set_custom_phrases(config.custom_phrases.clone()) {
        tracing::warn!(%error, "自定义短语有冲突，没应用");
    }
    engine.log_session(env!("CARGO_PKG_VERSION"), "linux");
    session::attach_cloud(&mut engine, &config.predict);
    let mut session = Session::new(engine, SessionConfig::from(&config));
    let model_path = find_model(&user_dir, &root);
    session.configure_local_model(model_path.clone(), &config.model);
    session.watch_config(&config, config_path, bundled_dicts_dir, Some(user_dir));
    let socket = args.socket.clone().unwrap_or_else(socket_path);
    tracing::info!(
        dict = %dict.display(),
        glossary = glossary.as_deref().map(|p| p.display().to_string()).unwrap_or_default(),
        language = language.code(),
        page_size = config.general.page_size(),
        shuangpin = config.general.shuangpin().map(|s| s.key()).unwrap_or("全拼"),
        fuzzy = config.fuzzy.any(),
        cloud = config.predict.enabled,
        model = model_path.as_deref().map(|p| p.display().to_string()).unwrap_or_default(),
        model_enabled = config.model.enabled,
        socket = %socket.display(),
        "青简 Linux 引擎服务就绪"
    );
    Service::new(session, socket).run();
}
