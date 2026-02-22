"""
CoOpt UI Patcher — Desktop app to update CoOpt UI project files in an MQ root from a GitHub repo manifest.
Run from MacroQuest root; only CoOpt UI files (ItemUI, ScriptTracker, macros, etc.) are updated.
"""

import os
import sys
import threading

import customtkinter as ctk
from PIL import Image

from updater import check_for_updates, patch
from validator import validate_mq_root


def resource_path(relative_path: str) -> str:
    """Absolute path to resource; works when running as script or as PyInstaller one-file exe."""
    try:
        base = sys._MEIPASS
    except AttributeError:
        base = os.path.abspath(os.path.dirname(__file__))
    return os.path.join(base, relative_path)


# Repo config: raw base URL (no trailing slash) and manifest path in repo
REPO_BASE_URL = "https://raw.githubusercontent.com/CooptGaming/CooptUI/feature/Updatetool"
MANIFEST_PATH = "release_manifest.json"

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
        self._patch_in_progress = False
        self._after_check_auto_patch = False

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

        self.auto_patch_var = ctk.BooleanVar(value=False)
        self.auto_patch_cb = ctk.CTkCheckBox(
            self.control_frame,
            text="Auto Patch",
            variable=self.auto_patch_var,
            font=ctk.CTkFont(weight="bold"),
            fg_color="#c0392b",
            hover_color="#a02820",
        )
        self.auto_patch_cb.pack(side="left", padx=8, pady=8)

        self.close_btn = ctk.CTkButton(
            self.control_frame,
            text="Close",
            font=ctk.CTkFont(weight="bold"),
            command=self.destroy,
            width=70,
        )
        self.close_btn.pack(side="right", padx=10, pady=8)

        self._run_validator_then_check()

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
        self._after_check_auto_patch = self.auto_patch_var.get()
        threading.Thread(target=self._check_updates, daemon=True).start()

    def _check_updates(self):
        to_update, err = check_for_updates(REPO_BASE_URL, self.mq_root, MANIFEST_PATH)
        self.after(0, lambda: self._on_check_done(to_update, err))

    def _on_check_done(self, to_update: list[dict], err: str | None):
        self.files_to_update = to_update
        if err:
            self._set_status(err)
            self.patch_btn.configure(state="disabled")
            return
        n = len(to_update)
        if n == 0:
            self._set_status("Up to date.")
            self.patch_btn.configure(state="disabled")
            return
        self._set_status(f"{n} file(s) to update.")
        self.patch_btn.configure(state="normal")
        if self._after_check_auto_patch:
            self._after_check_auto_patch = False
            self._on_patch()

    def _on_patch(self):
        if self._patch_in_progress or not self.files_to_update:
            return
        self._patch_in_progress = True
        self.patch_btn.configure(state="disabled")
        self._set_status("Patching…", show_progress=True, progress_val=0.0)

        def progress_cb(current: int, total: int, path_or_msg: str):
            def update():
                self._set_status(
                    f"Patching… {current}/{total}",
                    show_progress=True,
                    progress_val=current / total if total else 0,
                )
            self.after(0, update)

        def run():
            success, message = patch(
                self.files_to_update,
                REPO_BASE_URL,
                self.mq_root,
                progress_callback=progress_cb,
            )
            self.after(0, lambda: self._on_patch_done(success, message))

        threading.Thread(target=run, daemon=True).start()

    def _on_patch_done(self, success: bool, message: str):
        self._patch_in_progress = False
        self._set_status(message)
        self.progress.pack_forget()
        self.status_label.pack(side="left", fill="x", expand=True)
        if success:
            self.files_to_update = []
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
