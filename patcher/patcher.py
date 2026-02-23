"""
CoOpt UI Patcher — Desktop app to update CoOpt UI project files in an MQ root from a GitHub repo manifest.
Run from MacroQuest root; only CoOpt UI files (ItemUI, ScriptTracker, macros, etc.) are updated.
"""

import os
import sys
import threading

import customtkinter as ctk
from PIL import Image

from updater import check_for_updates, check_for_default_config, patch, install_default_config
from validator import validate_mq_root


def resource_path(relative_path: str) -> str:
    """Absolute path to resource; works when running as script or as PyInstaller one-file exe."""
    try:
        base = sys._MEIPASS
    except AttributeError:
        base = os.path.abspath(os.path.dirname(__file__))
    return os.path.join(base, relative_path)


# Repo config: raw base URL (no trailing slash) and manifest paths in repo
REPO_BASE_URL = "https://raw.githubusercontent.com/CooptGaming/CooptUI/master"
MANIFEST_PATH = "release_manifest.json"
DEFAULT_CONFIG_MANIFEST_PATH = "default_config_manifest.json"

WIDTH = 400
HEIGHT = 420
BANNER_HEIGHT = 320
CONTROL_BAR_HEIGHT = 50
STATUS_HEIGHT = 28


class PatcherApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("CoOpt UI Patcher")
        self.geometry(f"{WIDTH}x{HEIGHT}")
        self.resizable(False, False)
        self.mq_root = os.getcwd()
        self.files_to_update: list[dict] = []
        self.files_to_install_defaults: list[dict] = []
        self._patch_in_progress = False

        # Banner (CTkImage requires PIL Image objects, not file paths)
        banner_path = resource_path(os.path.join("assets", "banner.png"))
        self.banner_image = None
        if os.path.isfile(banner_path):
            try:
                pil_img = Image.open(banner_path).convert("RGBA")
                self.banner_image = ctk.CTkImage(
                    light_image=pil_img,
                    dark_image=pil_img,
                    size=(WIDTH, BANNER_HEIGHT),
                )
            except Exception:
                pass
        self.banner_label = ctk.CTkLabel(
            self, text="", image=self.banner_image, fg_color="transparent"
        )
        self.banner_label.pack(fill="x", padx=0, pady=0)
        if not self.banner_image:
            self.banner_label.configure(text="CoOpt UI Patcher", height=BANNER_HEIGHT)

        # Overlay over banner: shown during patch, lists each file being downloaded
        self.banner_overlay = ctk.CTkFrame(
            self, fg_color=("gray85", "gray20"), corner_radius=8, border_width=1, height=BANNER_HEIGHT
        )
        self.patch_log_text = ctk.CTkTextbox(
            self.banner_overlay,
            width=WIDTH - 24,
            height=BANNER_HEIGHT - 24,
            font=ctk.CTkFont(size=12),
            state="disabled",
            wrap="word",
        )
        self.patch_log_text.pack(padx=8, pady=8, fill="both", expand=True)
        # Position over banner; initially hidden
        self.banner_overlay.place(relx=0.5, rely=0, anchor="n", relwidth=1.0)
        self.banner_overlay.place_forget()

        # Status area (slim: progress or text)
        self.status_frame = ctk.CTkFrame(self, fg_color="transparent", height=STATUS_HEIGHT)
        self.status_frame.pack(fill="x", padx=8, pady=(4, 0))
        self.status_frame.pack_propagate(False)
        self.status_label = ctk.CTkLabel(
            self.status_frame, text="Checking…", font=ctk.CTkFont(weight="bold"), anchor="w"
        )
        self.status_label.pack(side="left", fill="x", expand=True)
        self.progress = ctk.CTkProgressBar(self.status_frame, width=WIDTH - 24)
        self.progress.pack(fill="x")
        self.progress.set(0)
        self.progress.pack_forget()

        # Control bar (light gray)
        self.control_frame = ctk.CTkFrame(
            self, fg_color="#d0d0d0", height=CONTROL_BAR_HEIGHT, corner_radius=0
        )
        self.control_frame.pack(side="bottom", fill="x", padx=0, pady=0)
        self.control_frame.pack_propagate(False)
        self.control_frame.configure(border_width=0)

        self.patch_btn = ctk.CTkButton(
            self.control_frame,
            text="Patch",
            fg_color="#c0392b",
            hover_color="#a02820",
            font=ctk.CTkFont(weight="bold"),
            command=self._on_patch,
            width=80,
        )
        self.patch_btn.pack(side="left", padx=(10, 8), pady=8)
        self.patch_btn.configure(state="disabled")

        self.close_btn = ctk.CTkButton(
            self.control_frame,
            text="Close",
            font=ctk.CTkFont(weight="bold"),
            command=self.destroy,
            width=70,
        )
        self.close_btn.pack(side="right", padx=10, pady=8)

        self._run_validator_then_check()

    def _patch_log_show(self):
        self.banner_overlay.place(relx=0.5, rely=0, anchor="n", relwidth=1.0)
        self.patch_log_text.configure(state="normal")
        self.patch_log_text.delete("0.0", "end")
        self.patch_log_text.configure(state="disabled")

    def _patch_log_append(self, line: str):
        self.patch_log_text.configure(state="normal")
        self.patch_log_text.insert("end", line + "\n")
        self.patch_log_text.see("end")
        self.patch_log_text.configure(state="disabled")

    def _patch_log_hide(self):
        self.banner_overlay.place_forget()

    def _set_status(self, text: str, show_progress: bool = False, progress_val: float = 0.0):
        self.status_label.configure(text=text)
        if show_progress:
            self.status_label.pack_forget()
            self.progress.pack(fill="x")
            self.progress.set(progress_val)
        else:
            self.progress.pack_forget()
            self.status_label.pack(side="left", fill="x", expand=True)

    def _run_validator_then_check(self):
        ok, msg = validate_mq_root(self.mq_root)
        if not ok:
            self._set_status(msg or "Invalid directory.")
            self.patch_btn.configure(state="disabled")
            return
        self._set_status("Checking for updates…")
        threading.Thread(target=self._check_updates, daemon=True).start()

    def _check_updates(self):
        to_update, err = check_for_updates(REPO_BASE_URL, self.mq_root, MANIFEST_PATH)
        if err:
            self.after(0, lambda: self._on_check_done(to_update, [], err))
            return
        to_install_defaults, default_err = check_for_default_config(
            REPO_BASE_URL, self.mq_root, DEFAULT_CONFIG_MANIFEST_PATH
        )
        if default_err:
            self.after(0, lambda: self._on_check_done(to_update, [], default_err))
            return
        self.after(0, lambda: self._on_check_done(to_update, to_install_defaults, None))

    def _on_check_done(self, to_update: list[dict], to_install_defaults: list[dict], err: str | None):
        self.files_to_update = to_update
        self.files_to_install_defaults = to_install_defaults or []
        if err:
            self._set_status(err)
            self.patch_btn.configure(state="disabled")
            return
        n_update = len(self.files_to_update)
        n_defaults = len(self.files_to_install_defaults)
        if n_update == 0 and n_defaults == 0:
            self._set_status("Up to date.")
            self.patch_btn.configure(state="disabled")
            return
        parts = []
        if n_update:
            parts.append(f"{n_update} file(s) to update")
        if n_defaults:
            parts.append(f"{n_defaults} default config to install")
        self._set_status(". ".join(parts) + ".")
        self.patch_btn.configure(state="normal")

    def _on_patch(self):
        if self._patch_in_progress or (not self.files_to_update and not self.files_to_install_defaults):
            return
        self._patch_in_progress = True
        self.patch_btn.configure(state="disabled")
        self._set_status("Patching…", show_progress=True, progress_val=0.0)
        self._patch_log_show()
        total_ops = len(self.files_to_update) + len(self.files_to_install_defaults)

        def progress_cb(current: int, total: int, path_or_msg: str):
            def update():
                self._set_status(
                    f"Patching… {current}/{total_ops}",
                    show_progress=True,
                    progress_val=current / total_ops if total_ops else 0,
                )
                if path_or_msg and path_or_msg != "Done":
                    self._patch_log_append(f"  {current}/{total_ops}: {path_or_msg}")
            self.after(0, update)

        def run():
            done = 0
            if self.files_to_update:
                success, message = patch(
                    self.files_to_update,
                    REPO_BASE_URL,
                    self.mq_root,
                    progress_callback=lambda c, t, p: progress_cb(done + c, total_ops, p),
                )
                if not success:
                    self.after(0, lambda: self._on_patch_done(False, message))
                    return
                done = len(self.files_to_update)
            if self.files_to_install_defaults:
                success, message = install_default_config(
                    self.files_to_install_defaults,
                    REPO_BASE_URL,
                    self.mq_root,
                    progress_callback=lambda c, t, p: progress_cb(done + c, total_ops, p),
                )
                self.after(0, lambda: self._on_patch_done(success, message))
            else:
                self.after(0, lambda: self._on_patch_done(True, "Update complete."))

        threading.Thread(target=run, daemon=True).start()

    def _on_patch_done(self, success: bool, message: str):
        self._patch_in_progress = False
        self._patch_log_hide()
        self._set_status(message)
        self.progress.pack_forget()
        self.status_label.pack(side="left", fill="x", expand=True)
        if success:
            self.files_to_update = []
            self.files_to_install_defaults = []
            self.patch_btn.configure(state="disabled")
        else:
            self.patch_btn.configure(state="normal")


def main():
    ctk.set_appearance_mode("dark")
    ctk.set_default_color_theme("blue")
    app = PatcherApp()
    # Window icon if available
    icon_path = resource_path(os.path.join("assets", "icon.ico"))
    if os.path.isfile(icon_path):
        app.iconbitmap(icon_path)
    app.mainloop()


if __name__ == "__main__":
    main()
