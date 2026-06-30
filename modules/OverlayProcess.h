static void reportAppStatus(NSString *status) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleIdentifier.length) {
        return;
    }
    @try {
        UIPasteboard *board = [UIPasteboard pasteboardWithName:kOverlayActiveAppsPasteboard create:YES];
        if (!board) {
            return;
        }
        NSString *existing = board.string ?: @"";
        NSMutableArray<NSString *> *kept = [NSMutableArray array];
        for (NSString *line in [existing componentsSeparatedByString:@"\n"]) {
            if (!line.length) {
                continue;
            }
            if ([line hasPrefix:[bundleIdentifier stringByAppendingString:@" "]]) {
                continue;  // bỏ dòng cũ của chính app này
            }
            [kept addObject:line];
        }
        [kept addObject:[NSString stringWithFormat:@"%@ %@", bundleIdentifier, status]];
        while (kept.count > 40) {
            [kept removeObjectAtIndex:0];
        }
        board.string = [kept componentsJoinedByString:@"\n"];
    } @catch (__unused id exception) {
    }
}

static BOOL shouldEnableOverlayInCurrentProcess(void) {
    // KIẾN TRÚC SpringBoard: CHỈ SpringBoard render overlay trên 1 UIWindow level
    // cực cao -> nổi trên mọi app + màn hình chính (như iPhone 6/7). Cần build arm64e
    // ĐÚNG CHUẨN (bằng Xcode/macOS qua GitHub Actions) thì mới nạp vào SpringBoard
    // arm64e mà không PAC-crash.
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}

// App thứ ba đủ điều kiện chạy "relay chạm" (chỉ phát hiện chạm ngoài ảnh -> báo
// SpringBoard toggle dim). KHÔNG vẽ gì, KHÔNG đọc file -> không dính sandbox, nhẹ.
static BOOL shouldRelayAppTouches(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    NSString *executablePath = NSBundle.mainBundle.executablePath;

    if (!bundleIdentifier.length || !bundlePath.length) {
        return NO;
    }
    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        return NO;  // SpringBoard tự xử lý chạm của nó
    }
    if ([bundleIdentifier hasPrefix:@"com.vietanh.overlayiostool"]) {
        return NO;  // app tool
    }
    if ([bundlePath containsString:@".appex"] || [executablePath containsString:@"/PlugIns/"]) {
        return NO;
    }
    if (![bundlePath hasSuffix:@".app"]) {
        return NO;
    }
    return [bundlePath hasPrefix:@"/var/containers/Bundle/Application/"] ||
           [bundlePath hasPrefix:@"/private/var/containers/Bundle/Application/"] ||
           [bundlePath hasPrefix:@"/Applications/"] ||
           [bundlePath hasPrefix:@"/var/jb/Applications/"] ||
           [bundlePath hasPrefix:@"/private/var/jb/Applications/"];
}

// SpringBoard công bố "overlay đang tương tác" (ảnh hiện + chế độ thường) qua notify
// state. App đọc để biết có cần relay chạm hay không. KHÔNG phụ thuộc toggle-click vì
// chạm trên ảnh phải mở panel kể cả khi toggle TẮT (SpringBoard tự quyết panel/dim).
static void updateToggleActiveState(void) {
    if (!gIsSpringBoardProcess) {
        return;
    }
    if (gSbToggleStateToken == 0) {
        notify_register_check(kOverlayToggleActiveState, &gSbToggleStateToken);
    }
    BOOL active = gOverlayImageView && gOverlayVisible && !gScaleLockModeEnabled;
    notify_set_state(gSbToggleStateToken, active ? 1 : 0);
    notify_post(kOverlayToggleActiveState);
}

// App: đọc nhanh state toggle-active (không dính sandbox).
static BOOL overlayToggleActiveForApp(void) {
    if (gAppToggleStateToken == 0) {
        return NO;
    }
    uint64_t state = 0;
    notify_get_state(gAppToggleStateToken, &state);
    return state != 0;
}

// LƯỚI AN TOÀN CHỐNG TREO TÁO — viết bằng C THUẦN (không phụ thuộc ObjC, vốn là
// thứ CÓ THỂ lỗi nếu ABI sai). Mỗi lần SpringBoard khởi động: tăng bộ đếm crash.
// Nếu crash >= 2 lần liên tiếp -> ghi cờ disabled -> tweak TỰ TẮT ngay lần sau ->
// máy vào được màn hình chính. Nếu SpringBoard sống qua 15s -> coi như khoẻ -> xoá
// bộ đếm. Tối đa 2 lần respring, KHÔNG bao giờ treo táo vĩnh viễn.
static BOOL springBoardCrashGuardShouldDisable(void) {
    static const char *kDir = "/var/mobile/Library/OverlayIOSTOOL";
    static const char *kDisabled = "/var/mobile/Library/OverlayIOSTOOL/disabled-after-crash";
    static const char *kCount = "/var/mobile/Library/OverlayIOSTOOL/sb-crash-count";

    mkdir(kDir, 0755);  // tạo thư mục nếu chưa có (bỏ qua nếu đã có)

    if (access(kDisabled, F_OK) == 0) {
        return YES;  // đã bị tắt từ trước -> không nạp
    }

    int count = 0;
    FILE *rf = fopen(kCount, "r");
    if (rf) {
        if (fscanf(rf, "%d", &count) != 1) {
            count = 0;
        }
        fclose(rf);
    }
    count += 1;

    if (count >= 2) {
        FILE *df = fopen(kDisabled, "w");
        if (df) { fputs("1", df); fclose(df); }
        unlink(kCount);
        NSLog(@"[OverlayIOSTOOL] Disabled after %d SpringBoard launch failures", count);
        return YES;  // crash 2 lần -> tắt ngay
    }

    FILE *wf = fopen(kCount, "w");
    if (wf) { fprintf(wf, "%d", count); fclose(wf); }

    // SpringBoard sống qua 15s -> khoẻ -> xoá bộ đếm (lần boot kế tính lại từ đầu).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        unlink(kCount);
    });
    return NO;
}

static UIPasteboard *overlayPasteboard(BOOL create) {
    return [UIPasteboard pasteboardWithName:kOverlayPasteboardName create:create];
}

