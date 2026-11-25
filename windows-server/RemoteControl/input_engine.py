"""Girdi motoru: Windows'ta doğrudan SendInput API'si.

Metin, KEYEVENTF_UNICODE ile UTF-16 kod birimi olarak gönderilir. Bu sayede
ğ ü ş ı İ ö ç (ve emoji) Windows klavye düzeninden bağımsız olarak doğru yazılır.
Windows dışı sistemlerde (Mac'te geliştirme) olayları sadece loglayan bir motor kullanılır.
"""

from __future__ import annotations

import logging
import sys
import threading

log = logging.getLogger(__name__)

# Özel tuş adları -> Windows Virtual-Key kodları
VK_CODES: dict[str, int] = {
    "backspace": 0x08, "tab": 0x09, "enter": 0x0D, "shift": 0x10, "ctrl": 0x11,
    "alt": 0x12, "pause": 0x13, "capslock": 0x14, "esc": 0x1B, "space": 0x20,
    "pageup": 0x21, "pagedown": 0x22, "end": 0x23, "home": 0x24,
    "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28,
    "printscreen": 0x2C, "insert": 0x2D, "delete": 0x2E,
    "win": 0x5B, "menu": 0x5D,
    "mute": 0xAD, "volumedown": 0xAE, "volumeup": 0xAF,
    "next": 0xB0, "prev": 0xB1, "playpause": 0xB3,
}
VK_CODES.update({f"f{i}": 0x6F + i for i in range(1, 25)})  # F1=0x70 ... F24=0x87

KEY_ALIASES = {
    "escape": "esc", "return": "enter", "del": "delete", "control": "ctrl",
    "cmd": "win", "super": "win", "meta": "win", "option": "alt",
    "arrowup": "up", "arrowdown": "down", "arrowleft": "left", "arrowright": "right",
    "pgup": "pageup", "pgdn": "pagedown",
}

# Bu tuşlar KEYEVENTF_EXTENDEDKEY bayrağı ister (aksi halde numpad tuşu gibi algılanır)
EXTENDED_VKS = frozenset({0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
                          0x2C, 0x2D, 0x2E, 0x5B, 0x5C, 0x5D})

# Metin içindeki kontrol karakterleri -> tuş
CONTROL_CHARS = {"\n": "enter", "\r": "enter", "\t": "tab", "\b": "backspace", "\x1b": "esc"}

MAX_TEXT_LEN = 2000


def normalize_key(name: str) -> str:
    key = str(name).strip().lower()
    return KEY_ALIASES.get(key, key)


class BaseInputEngine:
    """Ortak arayüz. Tüm metotlar asyncio iş parçacığından çağrılır."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._held_buttons: set[str] = set()

    # --- Fare ---
    def move_relative(self, dx: int, dy: int) -> None: ...
    def wheel(self, vertical: int, horizontal: int) -> None: ...
    def _button_event(self, button: str, down: bool) -> None: ...

    def button(self, button: str, down: bool) -> None:
        with self._lock:
            if down:
                if button in self._held_buttons:
                    return
                self._held_buttons.add(button)
            else:
                if button not in self._held_buttons:
                    return
                self._held_buttons.discard(button)
            self._button_event(button, down)

    def click(self, button: str, count: int = 1) -> None:
        count = max(1, min(int(count), 3))
        with self._lock:
            for _ in range(count):
                self._button_event(button, True)
                self._button_event(button, False)

    # --- Klavye ---
    def type_text(self, text: str) -> None: ...
    def key_tap(self, name: str) -> None: ...
    def key_combo(self, names: list[str]) -> None: ...

    def release_all(self) -> None:
        """Bağlantı koparsa basılı kalan tuşları bırak (sürükleme yarıda kalmasın)."""
        with self._lock:
            for button in list(self._held_buttons):
                self._button_event(button, False)
            self._held_buttons.clear()


class LoggingInputEngine(BaseInputEngine):
    """Windows dışı sistemler için: olayları uygulamaz, sadece loglar."""

    def __init__(self) -> None:
        super().__init__()
        log.warning("Windows dışı sistem: girdi olayları UYGULANMAYACAK, sadece loglanacak.")

    def move_relative(self, dx, dy):
        log.debug("move %d,%d", dx, dy)

    def wheel(self, vertical, horizontal):
        log.info("wheel v=%d h=%d", vertical, horizontal)

    def _button_event(self, button, down):
        log.info("button %s %s", button, "down" if down else "up")

    def type_text(self, text):
        log.info("text %r", text[:MAX_TEXT_LEN])

    def key_tap(self, name):
        log.info("key %s", normalize_key(name))

    def key_combo(self, names):
        log.info("combo %s", "+".join(normalize_key(n) for n in names))


if sys.platform == "win32":
    import ctypes
    from ctypes import wintypes

    user32 = ctypes.WinDLL("user32", use_last_error=True)

    INPUT_MOUSE = 0
    INPUT_KEYBOARD = 1

    MOUSEEVENTF_MOVE = 0x0001
    MOUSEEVENTF_LEFTDOWN = 0x0002
    MOUSEEVENTF_LEFTUP = 0x0004
    MOUSEEVENTF_RIGHTDOWN = 0x0008
    MOUSEEVENTF_RIGHTUP = 0x0010
    MOUSEEVENTF_MIDDLEDOWN = 0x0020
    MOUSEEVENTF_MIDDLEUP = 0x0040
    MOUSEEVENTF_WHEEL = 0x0800
    MOUSEEVENTF_HWHEEL = 0x1000

    KEYEVENTF_EXTENDEDKEY = 0x0001
    KEYEVENTF_KEYUP = 0x0002
    KEYEVENTF_UNICODE = 0x0004

    ULONG_PTR = ctypes.c_size_t

    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG),
                    ("mouseData", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                    ("time", wintypes.DWORD), ("dwExtraInfo", ULONG_PTR)]

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD),
                    ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD),
                    ("dwExtraInfo", ULONG_PTR)]

    class HARDWAREINPUT(ctypes.Structure):
        _fields_ = [("uMsg", wintypes.DWORD), ("wParamL", wintypes.WORD),
                    ("wParamH", wintypes.WORD)]

    class _INPUTUNION(ctypes.Union):
        _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT), ("hi", HARDWAREINPUT)]

    class INPUT(ctypes.Structure):
        _anonymous_ = ("u",)
        _fields_ = [("type", wintypes.DWORD), ("u", _INPUTUNION)]

    user32.SendInput.argtypes = (wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int)
    user32.SendInput.restype = wintypes.UINT
    user32.MapVirtualKeyW.argtypes = (wintypes.UINT, wintypes.UINT)
    user32.MapVirtualKeyW.restype = wintypes.UINT
    user32.VkKeyScanW.argtypes = (wintypes.WCHAR,)
    user32.VkKeyScanW.restype = ctypes.c_short

    _BUTTON_FLAGS = {
        "left": (MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP),
        "right": (MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP),
        "middle": (MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP),
    }

    def _mouse(flags: int, dx: int = 0, dy: int = 0, data: int = 0) -> INPUT:
        inp = INPUT(type=INPUT_MOUSE)
        inp.mi = MOUSEINPUT(dx, dy, data & 0xFFFFFFFF, flags, 0, 0)
        return inp

    def _key_vk(vk: int, up: bool) -> INPUT:
        flags = KEYEVENTF_KEYUP if up else 0
        if vk in EXTENDED_VKS:
            flags |= KEYEVENTF_EXTENDEDKEY
        scan = user32.MapVirtualKeyW(vk, 0) & 0xFFFF
        inp = INPUT(type=INPUT_KEYBOARD)
        inp.ki = KEYBDINPUT(vk, scan, flags, 0, 0)
        return inp

    def _key_unicode(code_unit: int, up: bool) -> INPUT:
        flags = KEYEVENTF_UNICODE | (KEYEVENTF_KEYUP if up else 0)
        inp = INPUT(type=INPUT_KEYBOARD)
        inp.ki = KEYBDINPUT(0, code_unit, flags, 0, 0)
        return inp

    def _send(inputs: list[INPUT]) -> None:
        if not inputs:
            return
        arr = (INPUT * len(inputs))(*inputs)
        sent = user32.SendInput(len(inputs), arr, ctypes.sizeof(INPUT))
        if sent != len(inputs):
            # Genellikle UIPI: yönetici olarak çalışan pencereye normal süreç girdi gönderemez
            log.debug("SendInput %d/%d (hata=%d)", sent, len(inputs), ctypes.get_last_error())

    def _vk_for(name: str) -> int | None:
        key = normalize_key(name)
        if key in VK_CODES:
            return VK_CODES[key]
        if len(key) == 1:
            ch = key.upper()
            if "A" <= ch <= "Z" or "0" <= ch <= "9":
                return ord(ch)
            res = user32.VkKeyScanW(key)
            if res != -1:
                return res & 0xFF
        return None

    class WindowsInputEngine(BaseInputEngine):
        def move_relative(self, dx: int, dy: int) -> None:
            if dx or dy:
                _send([_mouse(MOUSEEVENTF_MOVE, dx, dy)])

        def wheel(self, vertical: int, horizontal: int) -> None:
            events = []
            if vertical:
                events.append(_mouse(MOUSEEVENTF_WHEEL, data=vertical))
            if horizontal:
                events.append(_mouse(MOUSEEVENTF_HWHEEL, data=horizontal))
            _send(events)

        def _button_event(self, button: str, down: bool) -> None:
            flags = _BUTTON_FLAGS.get(button)
            if flags:
                _send([_mouse(flags[0] if down else flags[1])])

        def type_text(self, text: str) -> None:
            events: list[INPUT] = []
            for ch in text[:MAX_TEXT_LEN]:
                special = CONTROL_CHARS.get(ch)
                if special:
                    vk = VK_CODES[special]
                    events += [_key_vk(vk, False), _key_vk(vk, True)]
                    continue
                data = ch.encode("utf-16-le")  # BMP dışı karakterler 2 kod birimi (surrogate)
                units = [int.from_bytes(data[i:i + 2], "little") for i in range(0, len(data), 2)]
                events += [_key_unicode(u, False) for u in units]
                events += [_key_unicode(u, True) for u in units]
            _send(events)

        def key_tap(self, name: str) -> None:
            vk = _vk_for(name)
            if vk is None:
                log.warning("Bilinmeyen tuş: %r", name)
                return
            _send([_key_vk(vk, False), _key_vk(vk, True)])

        def key_combo(self, names: list[str]) -> None:
            vks = []
            for name in names[:5]:
                vk = _vk_for(name)
                if vk is None:
                    log.warning("Kombinasyonda bilinmeyen tuş: %r", name)
                    return
                vks.append(vk)
            down = [_key_vk(vk, False) for vk in vks]
            up = [_key_vk(vk, True) for vk in reversed(vks)]
            _send(down + up)


def create_input_engine() -> BaseInputEngine:
    if sys.platform == "win32":
        return WindowsInputEngine()
    return LoggingInputEngine()
