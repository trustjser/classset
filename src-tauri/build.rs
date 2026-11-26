fn main() {
    println!("cargo:rerun-if-changed=icons");
    println!("cargo:rerun-if-changed=Info.plist");
    #[cfg(target_os = "macos")]
    if std::env::var("PROFILE").as_deref() == Ok("debug") {
        let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        println!(
            "cargo:rustc-link-arg=-Wl,-sectcreate,__TEXT,__info_plist,{manifest_dir}/Info.plist"
        );
    }
    tauri_build::build()
}
