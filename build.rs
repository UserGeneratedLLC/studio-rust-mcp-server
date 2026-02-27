use std::process::Command;

fn run(cmd: &str, args: &[&str]) {
    let status = Command::new(cmd)
        .args(args)
        .status()
        .unwrap_or_else(|e| panic!("Failed to run `{cmd}`: {e}"));
    assert!(status.success(), "`{cmd}` exited with {status}");
}

fn main() {
    let out_dir = std::env::var_os("OUT_DIR").unwrap();
    let dest_path = std::path::PathBuf::from(&out_dir).join("MCPStudioPlugin.rbxm");

    std::fs::create_dir_all("Packages").ok();

    run(
        "rojo",
        &["sourcemap", "plugin.project.json", "-o", "sourcemap.json"],
    );

    run(
        "darklua",
        &[
            "process",
            "--config",
            ".darklua.json",
            "plugin",
            "plugin-build",
        ],
    );

    run(
        "rojo",
        &[
            "build",
            "plugin-build.project.json",
            "-o",
            &dest_path.to_string_lossy(),
        ],
    );

    println!("cargo:rerun-if-changed=plugin");
}
