"""
CoOpt UI Patcher v2 — Desktop app to update CoOpt UI project files in a MacroQuest root.
Two-state GUI: Setup (first-run / folder selection) and Main (update / patch).
Can be launched from anywhere — no longer requires running from the MQ root directory.
"""

import os
import sys
import threading
import tkinter.filedialog as filedialog

import customtkinter as ctk
from PIL import Image

from config import load as load_config, save as save_config, add_recent_path
from fresh_install import get_latest_release_zip_url, download_and_extract_zip
from migrate_itemui_to_coopui import migrate_itemui_to_coopui, ensure_env_after_patch
from path_finder import find_mq_installations
from updater import (
    check_for_default_config,
    check_for_updates,
    get_installed_version,
    install_default_config,
    patch,
    verify_installation,
    write_installed_version,
)
from validator import ensure_directories, validate_mq_root

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REPO_BASE_URL = "https://raw.githubusercontent.com/CooptGaming/CooptUI/main"
MANIFEST_PATH = "release_manifest.json"
DEFAULT_CONFIG_MANIFEST_PATH = "default_config_manifest.json"

# Window
WIDTH = 520
HEIGHT = 580

# Brand colours
NAVY = "#1a2332"
ORANGE = "#e86a1b"
ORANGE_HOVER = "#c85a15"
SUCCESS_GREEN = "#27ae60"
ERROR_RED = "#c0392b"
BODY_BG = "#2b2b2b"
CARD_BG = "#363636"
TEXT_DIM = "#999999"


def resource_path(relative_path: str) -> str:
    """Absolute path to resource; works as script or PyInstaller one-file exe."""
    try:
        base = sys._MEIPASS
    except AttributeError:
        base = os.path.abspath(os.path.dirname(__file__))
    return os.path.join(base, relative_path)


# ---------------------------------------------------------------------------
# SetupView — first-run / folder selection
# ---------------------------------------------------------------------------

class SetupView(ctk.CTkFrame):
    """Welcome screen with two-path onboarding."""

    def __init__(self, parent, app: "PatcherApp"):
        super().__init__(parent, fg_color="transparent")
        self.app = app

        # Heading
        ctk.CTkLabel(
            self, text="Welcome to CoOpt UI",
            font=ctk.CTkFont(size=20, weight="bold"),
        ).pack(pady=(24, 4))
        ctk.CTkLabel(
            self, text="How would you like to get started?",
            font=ctk.CTkFont(size=13), text_color=TEXT_DIM,
        ).pack(pady=(0, 16))

        # --- Option cards ---
        self._make_card(
            title="I already have MacroQuest",
            subtitle="Select your MQ folder to patch CoOpt UI",
            command=self._on_browse_existing,
        )
        self._make_card(
            title="Fresh install",
            subtitle="Download CoOpt UI into a new folder",
            command=self._on_fresh_install,
        )

        # --- Detected installs ---
        detected = find_mq_installations()
        recent = app.config.get("recent_paths", [])
        # Merge detected + recent, dedup, limit
        shown = []
        seen = set()
        for p in detected + recent:
            norm = os.path.normpath(p)
            if norm not in seen and os.path.isdir(p):
                seen.add(norm)
                shown.append(p)
        shown = shown[:6]

        if shown:
            sep = ctk.CTkFrame(self, fg_color=TEXT_DIM, height=1)
            sep.pack(fill="x", padx=24, pady=(20, 8))

            ctk.CTkLabel(
                self, text="Detected & recent installs",
                font=ctk.CTkFont(size=12, weight="bold"), text_color=TEXT_DIM,
                anchor="w",
            ).pack(fill="x", padx=28, pady=(4, 4))

            for path in shown:
                row = ctk.CTkFrame(self, fg_color="transparent")
                row.pack(fill="x", padx=28, pady=2)
                ctk.CTkLabel(
                    row, text=path, font=ctk.CTkFont(size=12),
                    anchor="w", text_color="#cccccc",
                ).pack(side="left", fill="x", expand=True)
                ctk.CTkButton(
                    row, text="Select", width=60,
                    font=ctk.CTkFont(size=11),
                    fg_color=NAVY, hover_color="#2a3a4f",
                    command=lambda p=path: self._on_select_path(p),
                ).pack(side="right", padx=(8, 0))

    def _make_card(self, title: str, subtitle: str, command):
        card = ctk.CTkFrame(self, fg_color=CARD_BG, corner_radius=8)
        card.pack(fill="x", padx=24, pady=6)
        inner = ctk.CTkFrame(card, fg_color="transparent")
        inner.pack(fill="x", padx=16, pady=12)
        ctk.CTkLabel(
            inner, text=title,
            font=ctk.CTkFont(size=14, weight="bold"), anchor="w",
        ).pack(fill="x")
        ctk.CTkLabel(
            inner, text=subtitle,
            font=ctk.CTkFont(size=12), text_color=TEXT_DIM, anchor="w",
        ).pack(fill="x", pady=(2, 0))
        btn = ctk.CTkButton(
            inner, text="Browse...", width=90,
            fg_color=ORANGE, hover_color=ORANGE_HOVER,
            font=ctk.CTkFont(weight="bold"),
            command=command,
        )
        btn.pack(anchor="e", pady=(8, 0))

    def _on_browse_existing(self):
        path = filedialog.askdirectory(title="Select MacroQuest Root Folder")
        if not path:
            return
        self._on_select_path(path)

    def _on_fresh_install(self):
        path = filedialog.askdirectory(title="Select Folder for Fresh Install")
        if not path:
            return
        self.app.show_fresh_install(path)

    def _on_select_path(self, path: str):
        is_valid, needs_setup, msg = validate_mq_root(path)
        if not is_valid:
            self.app.set_status(msg, error=True)
            return
        if needs_setup:
            ok, err = ensure_directories(path)
            if not ok:
                self.app.set_status(err, error=True)
                return
        self.app.show_main(path)


# ---------------------------------------------------------------------------
# MainView — normal update / patch flow
# ---------------------------------------------------------------------------

class MainView(ctk.CTkFrame):
    """Update check and patching interface."""

    def __init__(self, parent, app: "PatcherApp", mq_root: str):
        super().__init__(parent, fg_color="transparent")
        self.app = app
        self.mq_root = mq_root
        self.files_to_update: list[dict] = []
        self.files_to_install_defaults: list[dict] = []
        self.manifest_version: str | None = None
        self.installed_version: str | None = None
        self.changelog: list[str] = []
        self._patch_in_progress = False

        # --- Path bar ---
        path_frame = ctk.CTkFrame(self, fg_color="transparent")
        path_frame.pack(fill="x", padx=16, pady=(16, 0))
        ctk.CTkLabel(
            path_frame, text="MacroQuest Root",
            font=ctk.CTkFont(size=11, weight="bold"), text_color=TEXT_DIM, anchor="w",
        ).pack(fill="x")

        path_row = ctk.CTkFrame(path_frame, fg_color="transparent")
        path_row.pack(fill="x", pady=(4, 0))
        self.path_entry = ctk.CTkEntry(
            path_row, font=ctk.CTkFont(size=12), state="disabled",
            fg_color=CARD_BG, border_color="#555555",
        )
        self.path_entry.pack(side="left", fill="x", expand=True)
        self.path_entry.configure(state="normal")
        self.path_entry.insert(0, mq_root)
        self.path_entry.configure(state="disabled")

        ctk.CTkButton(
            path_row, text="Change", width=70,
            font=ctk.CTkFont(size=11),
            fg_color=NAVY, hover_color="#2a3a4f",
            command=self._on_change_folder,
        ).pack(side="right", padx=(8, 0))

        # Validation status
        self.valid_label = ctk.CTkLabel(
            self, text="", font=ctk.CTkFont(size=11),
            text_color=SUCCESS_GREEN, anchor="w",
        )
        self.valid_label.pack(fill="x", padx=20, pady=(4, 0))

        # --- Update info panel ---
        self.update_frame = ctk.CTkFrame(self, fg_color=CARD_BG, corner_radius=8)
        self.update_frame.pack(fill="x", padx=16, pady=(12, 0))

        self.update_title = ctk.CTkLabel(
            self.update_frame, text="Checking for updates...",
            font=ctk.CTkFont(size=14, weight="bold"), anchor="w",
        )
        self.update_title.pack(fill="x", padx=16, pady=(12, 0))

        self.update_subtitle = ctk.CTkLabel(
            self.update_frame, text="",
            font=ctk.CTkFont(size=12), text_color=TEXT_DIM, anchor="w",
        )
        self.update_subtitle.pack(fill="x", padx=16, pady=(2, 0))

        # Changelog area (scrollable)
        self.changelog_box = ctk.CTkTextbox(
            self.update_frame, height=140,
            font=ctk.CTkFont(size=12), fg_color="#2e2e2e",
            state="disabled", wrap="word",
        )
        self.changelog_box.pack(fill="x", padx=16, pady=(8, 12))
        self.changelog_box.pack_forget()  # Hidden until we have changelog data

        # --- Progress area ---
        self.progress_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.progress_frame.pack(fill="x", padx=16, pady=(12, 0))

        self.progress_bar = ctk.CTkProgressBar(
            self.progress_frame, width=WIDTH - 48,
            progress_color=ORANGE,
        )
        self.progress_bar.pack(fill="x")
        self.progress_bar.set(0)
        self.progress_bar.pack_forget()

        self.progress_label = ctk.CTkLabel(
            self.progress_frame, text="",
            font=ctk.CTkFont(size=11), text_color=TEXT_DIM, anchor="w",
        )
        self.progress_label.pack(fill="x", pady=(4, 0))
        self.progress_label.pack_forget()

        # --- Patch log (shows during patching) ---
        self.patch_log = ctk.CTkTextbox(
            self, height=120,
            font=ctk.CTkFont(size=11), fg_color="#1e1e1e",
            state="disabled", wrap="word",
        )
        self.patch_log.pack(fill="x", padx=16, pady=(8, 0))
        self.patch_log.pack_forget()

        # Start update check
        self._run_migration_and_check()

    def _run_migration_and_check(self):
        """Run migration, then check for updates."""
        def _migrate_log(line: str):
            self.after(0, lambda: self.app.set_status(line[:80]))

        migrate_ok, migrate_msg = migrate_itemui_to_coopui(self.mq_root, log_callback=_migrate_log)
        if not migrate_ok:
            self.app.set_status(migrate_msg or "Migration failed.", error=True)
            return

        installed = get_installed_version(self.mq_root)
        ver_text = f"Valid install"
        if installed:
            ver_text += f" · CoOpt UI v{installed}"
        self.valid_label.configure(text=f"  {ver_text}", text_color=SUCCESS_GREEN)

        threading.Thread(target=self._check_updates, daemon=True).start()

    def _check_updates(self):
        to_update, manifest_version, err = check_for_updates(
            REPO_BASE_URL, self.mq_root, MANIFEST_PATH
        )
        installed_version = get_installed_version(self.mq_root)

        # Try to extract changelog from manifest
        changelog = []
        try:
            import json
            import urllib.request
            manifest_url = f"{REPO_BASE_URL.rstrip('/')}/{MANIFEST_PATH}"
            req = urllib.request.Request(manifest_url)
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8", errors="replace"))
            changelog = data.get("changelog", [])
        except Exception:
            pass

        if err:
            self.after(0, lambda: self._on_check_done(to_update, [], err, manifest_version, installed_version, changelog))
            return

        to_install_defaults, default_err = check_for_default_config(
            REPO_BASE_URL, self.mq_root, DEFAULT_CONFIG_MANIFEST_PATH
        )
        combined_err = default_err if default_err else None
        self.after(0, lambda: self._on_check_done(
            to_update, to_install_defaults or [], combined_err,
            manifest_version, installed_version, changelog
        ))

    def _on_check_done(
        self,
        to_update: list[dict],
        to_install_defaults: list[dict],
        err: str | None,
        manifest_version: str | None,
        installed_version: str | None,
        changelog: list[str],
    ):
        self.files_to_update = to_update
        self.files_to_install_defaults = to_install_defaults
        self.manifest_version = manifest_version
        self.installed_version = installed_version
        self.changelog = changelog

        if err:
            self.update_title.configure(text="Error checking for updates")
            self.update_subtitle.configure(text=err, text_color=ERROR_RED)
            self.app.set_primary_button("Retry", self._retry_check, enabled=True, color=ORANGE)
            return

        n_update = len(self.files_to_update)
        n_defaults = len(self.files_to_install_defaults)

        if n_update == 0 and n_defaults == 0:
            ver = (manifest_version or installed_version or "").strip() or None
            title = f"Up to date" + (f" (v{ver})" if ver else "")
            self.update_title.configure(text=title)
            self.update_subtitle.configure(text="All files match the latest release.", text_color=SUCCESS_GREEN)
            self.app.set_primary_button("Up to Date", None, enabled=False, color=SUCCESS_GREEN)
            return

        # Updates available
        parts = []
        if n_update:
            parts.append(f"{n_update} file(s) to update")
        if n_defaults:
            parts.append(f"{n_defaults} default config to install")

        inst = (installed_version or "new install").strip()
        avail = (manifest_version or "latest").strip()
        self.update_title.configure(text=f"Update Available: {inst} \u2192 {avail}")
        self.update_subtitle.configure(text=" · ".join(parts), text_color="#ffffff")

        # Show changelog if available
        if changelog:
            self.changelog_box.pack(fill="x", padx=16, pady=(8, 12))
            self.changelog_box.configure(state="normal")
            self.changelog_box.delete("0.0", "end")
            for entry in changelog:
                if entry.startswith("### "):
                    self.changelog_box.insert("end", f"\n{entry[4:]}\n")
                else:
                    self.changelog_box.insert("end", f"  \u2022 {entry}\n")
            self.changelog_box.configure(state="disabled")

        self.app.set_primary_button("Update", self._on_patch, enabled=True, color=ORANGE)

    def _retry_check(self):
        self.update_title.configure(text="Checking for updates...")
        self.update_subtitle.configure(text="", text_color=TEXT_DIM)
        self.app.set_primary_button("Update", None, enabled=False, color=ORANGE)
        threading.Thread(target=self._check_updates, daemon=True).start()

    def _on_patch(self):
        if self._patch_in_progress or (not self.files_to_update and not self.files_to_install_defaults):
            return
        self._patch_in_progress = True
        self.app.set_primary_button("Updating...", None, enabled=False, color=ORANGE)

        # Show progress UI
        self.progress_bar.pack(fill="x")
        self.progress_bar.set(0)
        self.progress_label.pack(fill="x", pady=(4, 0))
        self.patch_log.pack(fill="x", padx=16, pady=(8, 0))
        self.patch_log.configure(state="normal")
        self.patch_log.delete("0.0", "end")
        self.patch_log.configure(state="disabled")

        total_ops = len(self.files_to_update) + len(self.files_to_install_defaults)

        def progress_cb(current: int, total: int, path_or_msg: str):
            def update():
                frac = current / total_ops if total_ops else 0
                self.progress_bar.set(frac)
                self.progress_label.configure(text=f"{current}/{total_ops}: {path_or_msg}")
                if path_or_msg and path_or_msg != "Done":
                    self.patch_log.configure(state="normal")
                    self.patch_log.insert("end", f"  {current}/{total_ops}: {path_or_msg}\n")
                    self.patch_log.see("end")
                    self.patch_log.configure(state="disabled")
            self.after(0, update)

        def run():
            done = 0
            if self.files_to_update:
                success, message = patch(
                    self.files_to_update, REPO_BASE_URL, self.mq_root,
                    progress_callback=lambda c, t, p: progress_cb(done + c, total_ops, p),
                )
                if not success:
                    self.after(0, lambda: self._on_patch_done(False, message))
                    return
                done = len(self.files_to_update)
            if self.files_to_install_defaults:
                success, message = install_default_config(
                    self.files_to_install_defaults, REPO_BASE_URL, self.mq_root,
                    progress_callback=lambda c, t, p: progress_cb(done + c, total_ops, p),
                )
                self.after(0, lambda: self._on_patch_done(success, message))
            else:
                self.after(0, lambda: self._on_patch_done(True, "Update complete."))

        threading.Thread(target=run, daemon=True).start()

    def _on_patch_done(self, success: bool, message: str):
        self._patch_in_progress = False
        self.progress_bar.set(1.0 if success else self.progress_bar.get())

        if success:
            ensure_env_after_patch(self.mq_root)
            # Post-patch verification
            if self.files_to_update:
                all_ok, failed = verify_installation(self.files_to_update, self.mq_root)
                if not all_ok:
                    message = (
                        f"Update complete but {len(failed)} file(s) failed verification. "
                        f"Check permissions or antivirus: {', '.join(failed[:3])}"
                    )
                else:
                    message += " All files verified."
            if self.manifest_version:
                write_installed_version(self.mq_root, self.manifest_version)
            self.files_to_update = []
            self.files_to_install_defaults = []
            self.update_title.configure(text="Update complete")
            self.update_subtitle.configure(text=message, text_color=SUCCESS_GREEN)
            self.progress_label.configure(text=message)
            self.app.set_primary_button("Up to Date", None, enabled=False, color=SUCCESS_GREEN)
            # Refresh validation label
            installed = get_installed_version(self.mq_root)
            if installed:
                self.valid_label.configure(text=f"  Valid install · CoOpt UI v{installed}")
        else:
            self.update_subtitle.configure(text=message, text_color=ERROR_RED)
            self.progress_label.configure(text=message)
            self.app.set_primary_button("Retry", self._on_patch, enabled=True, color=ORANGE)

    def _on_change_folder(self):
        self.app.show_setup()


# ---------------------------------------------------------------------------
# PatcherApp — main application window
# ---------------------------------------------------------------------------

class PatcherApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("CoOpt UI Patcher")
        self.geometry(f"{WIDTH}x{HEIGHT}")
        self.resizable(False, False)
        self.config = load_config()

        # --- Header bar (navy) ---
        self.header = ctk.CTkFrame(self, fg_color=NAVY, height=50, corner_radius=0)
        self.header.pack(fill="x")
        self.header.pack_propagate(False)

        # Logo icon
        self.logo_image = None
        banner_path = resource_path(os.path.join("assets", "banner.png"))
        if os.path.isfile(banner_path):
            try:
                pil_img = Image.open(banner_path).convert("RGBA")
                self.logo_image = ctk.CTkImage(
                    light_image=pil_img, dark_image=pil_img,
                    size=(36, 36),
                )
            except Exception:
                pass

        if self.logo_image:
            ctk.CTkLabel(
                self.header, text="", image=self.logo_image,
                fg_color="transparent",
            ).pack(side="left", padx=(12, 4))

        ctk.CTkLabel(
            self.header, text="CoOpt UI Patcher",
            font=ctk.CTkFont(size=16, weight="bold"),
            text_color="#ffffff",
        ).pack(side="left", padx=(4, 0))

        self.version_label = ctk.CTkLabel(
            self.header, text="",
            font=ctk.CTkFont(size=11), text_color=TEXT_DIM,
        )
        self.version_label.pack(side="right", padx=16)

        # --- Body frame ---
        self.body = ctk.CTkFrame(self, fg_color=BODY_BG, corner_radius=0)
        self.body.pack(fill="both", expand=True)

        # --- Status label (inline, below body) ---
        self.status_label = ctk.CTkLabel(
            self, text="", font=ctk.CTkFont(size=11),
            text_color=TEXT_DIM, anchor="w", height=20,
        )
        self.status_label.pack(fill="x", padx=16, pady=(0, 0))

        # --- Footer bar (navy) ---
        self.footer = ctk.CTkFrame(self, fg_color=NAVY, height=56, corner_radius=0)
        self.footer.pack(fill="x", side="bottom")
        self.footer.pack_propagate(False)

        self.close_btn = ctk.CTkButton(
            self.footer, text="Close",
            font=ctk.CTkFont(weight="bold"),
            fg_color="#555555", hover_color="#666666",
            command=self.destroy, width=80,
        )
        self.close_btn.pack(side="right", padx=16, pady=10)

        self.primary_btn = ctk.CTkButton(
            self.footer, text="Update",
            font=ctk.CTkFont(weight="bold"),
            fg_color=ORANGE, hover_color=ORANGE_HOVER,
            width=120, state="disabled",
        )
        self.primary_btn.pack(side="right", padx=(0, 8), pady=10)

        # --- Decide initial state ---
        saved_root = self.config.get("mq_root", "")
        if saved_root and os.path.isdir(saved_root):
            is_valid, needs_setup, _ = validate_mq_root(saved_root)
            if is_valid:
                if needs_setup:
                    ensure_directories(saved_root)
                self.show_main(saved_root, save=False)
                return
        self.show_setup()

    def set_status(self, text: str, error: bool = False):
        """Update the inline status label."""
        color = ERROR_RED if error else TEXT_DIM
        self.status_label.configure(text=text, text_color=color)

    def set_primary_button(self, text: str, command=None, enabled: bool = True, color: str = ORANGE):
        """Update the footer's primary button."""
        self.primary_btn.configure(
            text=text,
            fg_color=color,
            hover_color=ORANGE_HOVER if color == ORANGE else color,
            state="normal" if enabled and command else "disabled",
            command=command if command else lambda: None,
        )

    def _clear_body(self):
        """Remove all children from the body frame."""
        for child in self.body.winfo_children():
            child.destroy()

    def show_setup(self):
        """Show the Setup/welcome view."""
        self._clear_body()
        self.set_status("")
        self.set_primary_button("Update", None, enabled=False)
        self.version_label.configure(text="")
        view = SetupView(self.body, self)
        view.pack(fill="both", expand=True)

    def show_main(self, mq_root: str, save: bool = True):
        """Show the Main update view for a validated MQ root."""
        if save:
            self.config = add_recent_path(self.config, mq_root)
            save_config(self.config)
        self._clear_body()
        self.set_status("")
        view = MainView(self.body, self, mq_root)
        view.pack(fill="both", expand=True)

    def show_fresh_install(self, target_dir: str):
        """Run the fresh install flow, then transition to Main view."""
        self._clear_body()
        self.set_status("")

        # Progress view during download
        progress_frame = ctk.CTkFrame(self.body, fg_color="transparent")
        progress_frame.pack(fill="both", expand=True, padx=24, pady=40)

        ctk.CTkLabel(
            progress_frame, text="Fresh Install",
            font=ctk.CTkFont(size=20, weight="bold"),
        ).pack(pady=(24, 4))

        status_label = ctk.CTkLabel(
            progress_frame, text="Finding latest release...",
            font=ctk.CTkFont(size=13), text_color=TEXT_DIM,
        )
        status_label.pack(pady=(0, 16))

        progress_bar = ctk.CTkProgressBar(progress_frame, progress_color=ORANGE)
        progress_bar.pack(fill="x", padx=24, pady=(0, 8))
        progress_bar.set(0)

        detail_label = ctk.CTkLabel(
            progress_frame, text="",
            font=ctk.CTkFont(size=11), text_color=TEXT_DIM,
        )
        detail_label.pack(fill="x", padx=24)

        self.set_primary_button("Installing...", None, enabled=False)

        def run():
            # Step 1: Find release URL
            zip_url, version, err = get_latest_release_zip_url()
            if err or not zip_url:
                self.after(0, lambda: self._fresh_install_error(err or "Could not find release."))
                return

            self.after(0, lambda: status_label.configure(
                text=f"Downloading CoOpt UI v{version or 'latest'}..."
            ))

            # Step 2: Download and extract
            def progress_cb(msg: str, frac: float):
                self.after(0, lambda: (
                    progress_bar.set(frac),
                    detail_label.configure(text=msg),
                ))

            success, message = download_and_extract_zip(zip_url, target_dir, progress_cb)
            if not success:
                self.after(0, lambda: self._fresh_install_error(message))
                return

            # Step 3: Transition to main view
            self.after(0, lambda: self.show_main(target_dir))

        threading.Thread(target=run, daemon=True).start()

    def _fresh_install_error(self, message: str):
        """Handle fresh install failure."""
        self.set_status(message, error=True)
        self.set_primary_button("Back", self.show_setup, enabled=True, color=NAVY)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    ctk.set_appearance_mode("dark")
    ctk.set_default_color_theme("blue")
    app = PatcherApp()
    icon_path = resource_path(os.path.join("assets", "icon.ico"))
    if os.path.isfile(icon_path):
        app.iconbitmap(icon_path)
    app.mainloop()


if __name__ == "__main__":
    main()
