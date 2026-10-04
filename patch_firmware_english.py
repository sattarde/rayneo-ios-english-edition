import zipfile, hashlib, json, os, struct

ZIP_INPUT = 'StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-EXPERIMENTAL.zip'
ZIP_OUTPUT = 'StrixOS-1.0.4.12-TurboFocus-TFP1-FOCUS04-ENGLISH.zip'

TRANSLATIONS = [
    # (offset, original_utf8, english_replacement)
    # The 12-item carousel items:
    (9521665, '录音', 'Record'),
    (9521042, '实时字幕', 'Captions'),
    (9520788, '实时提示', 'Prompts'),
    (9521557, '待办', 'To-Do'),
    (9522037, '提词器', 'Prompter'),
    (9522170, '全天智记', 'LifeLog'),
    (9521905, '勿扰模式', 'Silent'),
    (9521278, '显示测试', 'Display Test'),
    (9522105, '导航', 'Nav'),
    (9521564, '网易云音乐', 'Music'),
    (9521580, '微信读书', 'Reader'),
    (9521291, '番茄时钟', 'Timer'),

    # Sub-pages and status headers:
    (9520764, '字/分  长按书架  ', 'wpm | Hold: Shelf    '),
    (9520801, '番茄时钟 · 专注', 'Focus · Working'),
    (9520836, '请在手机同步书架', 'Sync shelf on phone'),
    (9520864, '再次长按退出 · 无需等待手机', 'Hold again to exit · Phone not needed'),
    (9520905, '歌词加载中…', 'Loading lyrics...'),
    (9520924, '准备好，专注一件事', 'Ready to focus on task'),
    (9520952, '短按继续 · 长按停止并退出', 'Click: Resume | Hold: Stop & Exit'),
    (9521004, '播放中', 'Playing'),
    (9521014, '时间到，休息一下。', "Time's up! Take a break."),
    (9521068, '按章加载', 'By Chapter'),
    (9521081, '请从手机开始导航', 'Start nav on phone'),
    (9521133, '● 专注计时中', '● Focusing...'),
    (9521170, '番茄时钟 · 长休息', 'Focus · Long Break'),
    (9521227, '短按暂停 · 长按停止 · 息屏继续计时', 'Click: Pause | Hold: Stop | Timer runs in sleep'),
    (9521354, '导航 · 常亮', 'Nav · Always On'),
    (9521371, '请在手机选择歌曲', 'Select song on phone'),
    (9521496, '正在返回书架…', 'Returning to shelf...'),
    (9521518, '长按返回', 'Hold: Back'),
    (9521531, '番茄时钟 · 短休息', 'Focus · Short Break'),
    (9521624, '短按开始下一阶段 · 长按退出', 'Click: Next Phase | Hold: Exit'),
    (9521677, '自动 ', 'Auto '),
    (9521685, '  加载中', ' Loading...'),
    (9521763, '正在加载下一页…', 'Loading next page...'),
    (9521788, '导航 · 60秒无更新息屏', 'Nav · Sleep after 60s idle'),
    (9521830, '旋钮选择   按下打开   长按退出', 'Scroll: Select  Click: Open  Hold: Exit'),
    (9521873, '安静计时 · 息屏后继续', 'Quiet Timer · Screen Off OK'),
    (9521949, '网页', 'Web'),
    (9521956, '滚动选时长 · 短按开始 · 长按退出', 'Scroll: Time | Click: Start | Hold: Exit'),
    (9522015, '已暂停', 'Paused'),
    (9522112, '导航数据已过期 · 请查看手机', 'Nav data expired · Check your phone'),
    (9522153, '微信读书    ', 'Reader      '),
    (9522183, '手动 ', 'Manual '),
]

def main():
    print(f"Reading {ZIP_INPUT}...")
    with zipfile.ZipFile(ZIP_INPUT, 'r') as zin:
        files = {}
        for info in zin.infolist():
            files[info.filename] = (info, zin.read(info.filename))

    ap = bytearray(files['nuttx_ap.bin'][1])
    orig_ap_len = len(ap)
    print(f"Original nuttx_ap.bin size: {orig_ap_len} bytes")

    patched_count = 0
    for offset, orig_text, eng_text in TRANSLATIONS:
        orig_bytes = orig_text.encode('utf-8')
        eng_bytes = eng_text.encode('utf-8')

        # Verify that original bytes exist at offset
        actual = ap[offset:offset+len(orig_bytes)]
        if actual != orig_bytes:
            raise ValueError(f"Mismatch at offset {offset}: expected {orig_bytes!r}, found {actual!r}")

        # Find the null terminator of the original string
        null_pos = ap.find(b'\x00', offset)
        avail_len = null_pos - offset
        if len(eng_bytes) > avail_len:
            raise ValueError(f"English string {eng_text!r} ({len(eng_bytes)} bytes) exceeds available {avail_len} bytes at offset {offset}")

        # Replace and pad with null bytes
        replacement = eng_bytes + b'\x00' * (avail_len - len(eng_bytes) + 1)
        ap[offset:offset+len(replacement)] = replacement
        patched_count += 1
        print(f"Patched [{orig_text}] -> [{eng_text}] at offset {offset} (used {len(eng_bytes)}/{avail_len} bytes)")

    assert len(ap) == orig_ap_len, f"Size changed: {len(ap)} != {orig_ap_len}"
    print(f"\nSuccessfully patched {patched_count} strings. nuttx_ap.bin size preserved: {len(ap)} bytes.")

    # Patch 5 paired() functions to return true (1) on iOS BLE/MFi without requiring Android SPP (0x80)
    BASE = 0x10190000
    PAIRED_SITES = [
        ("nav_paired",         0x10a9c788),
        ("music_paired",       0x10a9dee6),
        ("diagnostics_paired", 0x10a9f3ae),
        ("reader_paired",      0x10aa1626),
        ("focus_paired",       0x10aa2f8a),
    ]
    for name, va in PAIRED_SITES:
        off = va - BASE
        prologue = bytes(ap[off:off+4])
        if prologue != bytes.fromhex("80b56f46"):
            raise ValueError(f"{name} prologue mismatch at {va:#x}: {prologue.hex()}")
        ap[off+4:off+8] = bytes.fromhex("012080bd")  # movs r0, #1; pop {r7, pc}
        print(f"Patched {name} @ {va:#x} (offset {off:#x}) -> movs r0, #1; pop {{r7, pc}}")

    # Patch 4 safe_home() / home() tail calls to LauncherAPI::isBussinessIdle (0x106d334c)
    # so LifeLog being enabled does not block opening Nav, Music, Reader, or Timer from the carousel
    HOME_TAIL_SITES = [
        ("nav_safe_home", 0x10a9c3dc, "36f4b6bf"),
        ("music_home",    0x10a9df5a, "35f4f7b9"),
        ("reader_home",   0x10aa169a, "31f457be"),
        ("focus_home",    0x10aa3282, "30f463b8"),
    ]
    for name, va, expected_hex in HOME_TAIL_SITES:
        off = va - BASE
        actual = bytes(ap[off:off+4])
        if actual != bytes.fromhex(expected_hex):
            raise ValueError(f"{name} tail-call mismatch at {va:#x}: expected {expected_hex}, got {actual.hex()}")
        ap[off:off+4] = bytes.fromhex("01207047")  # movs r0, #1; bx lr
        print(f"Patched {name} @ {va:#x} (offset {off:#x}) -> movs r0, #1; bx lr")

    assert len(ap) == orig_ap_len, f"Size changed after binary patch: {len(ap)} != {orig_ap_len}"

    new_ap_bytes = bytes(ap)
    new_ap_md5 = hashlib.md5(new_ap_bytes).hexdigest()
    new_ap_sha256 = hashlib.sha256(new_ap_bytes).hexdigest()
    print(f"New nuttx_ap.bin MD5:    {new_ap_md5}")
    print(f"New nuttx_ap.bin SHA256: {new_ap_sha256}")

    # Update OtaFileInfo.json
    ota_info_bytes = files['OtaFileInfo.json'][1]
    ota_info = json.loads(ota_info_bytes.decode('utf-8'))
    for item in ota_info:
        if item.get("Name") == "nuttx_ap.bin":
            print(f"Updating OtaFileInfo.json for nuttx_ap.bin: MD5 was {item['Md5']}, now {new_ap_md5}")
            item["Md5"] = new_ap_md5

    new_ota_info_bytes = json.dumps(ota_info, indent=2).encode('utf-8') + b'\n'
    new_ota_info_sha256 = hashlib.sha256(new_ota_info_bytes).hexdigest()
    print(f"New OtaFileInfo.json Size: {len(new_ota_info_bytes)} bytes, SHA256: {new_ota_info_sha256}")

    # Repack zip with exact member order
    if os.path.exists(ZIP_OUTPUT):
        os.remove(ZIP_OUTPUT)

    with zipfile.ZipFile(ZIP_OUTPUT, 'w', compression=zipfile.ZIP_DEFLATED) as zout:
        for fname in [
            'OtaFileInfo.json',
            'nuttx_audio.bin',
            'cb_fw_venus.bin',
            'nuttx_ap.bin',
            'ota_installer_progress.bin',
            'images.bin',
            'lotties.bin',
            'rives.bin',
            'nuttx_bth.bin',
            'fac_test_img.bin',
            'nuttx_apc1.bin',
            'smf.json',
            'pil_algo_vad_demo.dll',
            'pil_algo_wakeup_dll_nand.dll',
            'pil_algo_up_demo_nand.dll'
        ]:
            if fname == 'nuttx_ap.bin':
                zout.writestr(fname, new_ap_bytes)
            elif fname == 'OtaFileInfo.json':
                zout.writestr(fname, new_ota_info_bytes)
            else:
                zout.writestr(fname, files[fname][1])

    new_zip_bytes = open(ZIP_OUTPUT, 'rb').read()
    new_zip_sha256 = hashlib.sha256(new_zip_bytes).hexdigest()
    print(f"\nCreated {ZIP_OUTPUT}:")
    print(f"  Size:   {len(new_zip_bytes)} bytes")
    print(f"  SHA256: {new_zip_sha256}")

    # Output constants for updating package.mjs and ExperimentalOTA.m
    print("\n--- CODE UPDATES REQUIRED ---")
    print(f"ZIP SHA256:         {new_zip_sha256}")
    print(f"ZIP Size:           {len(new_zip_bytes)}")
    print(f"nuttx_ap.bin SHA256:{new_ap_sha256}")
    print(f"nuttx_ap.bin MD5:   {new_ap_md5}")
    print(f"OtaFileInfo SHA256: {new_ota_info_sha256}")
    print(f"OtaFileInfo Size:   {len(new_ota_info_bytes)}")

if __name__ == '__main__':
    main()
