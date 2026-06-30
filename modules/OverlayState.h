static NSDictionary *overlayStateDictionary(void) {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"scaleLockModeEnabled"] = @(gScaleLockModeEnabled);
    state[@"overlayVisible"] = @(gOverlayVisible);
    state[@"overlayDimmed"] = @(gOverlayDimmed);
    state[@"dimOpacity"] = @(gDimOpacity);
    state[@"dimAnimationMs"] = @(gDimAnimationMs);
    state[@"activeImageIndex"] = @(gActiveImageIndex);

    if (gOverlayImageView) {
        CGRect frame = gOverlayImageView.frame;       // ẢNH 1 -> khóa "frame" (tương thích ngược)
        state[@"frame"] = @{
            @"x": @(frame.origin.x),
            @"y": @(frame.origin.y),
            @"w": @(frame.size.width),
            @"h": @(frame.size.height)
        };
    }
    if (gOverlayImageView2) {
        CGRect frame2 = gOverlayImageView2.frame;      // ẢNH 2 -> khóa "frame2"
        state[@"frame2"] = @{
            @"x": @(frame2.origin.x),
            @"y": @(frame2.origin.y),
            @"w": @(frame2.size.width),
            @"h": @(frame2.size.height)
        };
    }

    return state;
}

static void persistOverlayState(BOOL broadcast) {
    if (!gOverlayImageView || gApplyingRemoteState) {
        return;
    }

    NSDictionary *state = overlayStateDictionary();
    [state writeToFile:kOverlayStatePath atomically:YES];
    if (broadcast) {
        notify_post(kOverlayStateNotification);
    }
}

static void applyRealtimeOverlayMessage(const OverlayRealtimeMessage *message) {
    if (!gIsSpringBoardProcess || !message || message->magic != kOverlayRealtimeMagic || !gOverlayImageView) {
        return;
    }

    gApplyingRemoteState = YES;
    gOverlayImageView.frame = CGRectMake(message->x, message->y, message->width, message->height);
    gOverlayVisible = message->visible;
    gOverlayDimmed = message->dimmed;
    gDimOpacity = MAX(0.0, MIN(message->dimOpacity, 1.0));
    gDimAnimationMs = MAX(0, MIN((NSInteger)message->dimAnimationMs, 10000));
    gScaleLockModeEnabled = message->scaleLock;
    gOverlayImageView.hidden = !gOverlayVisible && !gScaleLockModeEnabled;
    gOverlayImageView.alpha = gOverlayDimmed ? gDimOpacity : 1.0;
    gOverlayImageView.layer.borderWidth = gScaleLockModeEnabled ? 3.0 : 0.0;
    gOverlayImageView.layer.borderColor = gScaleLockModeEnabled ? UIColor.systemBlueColor.CGColor : nil;
    updateOverlayControlValues();
    updateScaleLockControlsVisibility();
    refreshOverlayWindowVisibility();
    gApplyingRemoteState = NO;
}

static void realtimeSocketCallback(CFSocketRef socket,
                                   CFSocketCallBackType type,
                                   CFDataRef address,
                                   const void *data,
                                   void *info) {
    if (type != kCFSocketDataCallBack || !data) {
        return;
    }

    CFDataRef packetData = (CFDataRef)data;
    if (CFDataGetLength(packetData) < (CFIndex)sizeof(OverlayRealtimeMessage)) {
        return;
    }

    OverlayRealtimeMessage message;
    memcpy(&message, CFDataGetBytePtr(packetData), sizeof(message));
    applyRealtimeOverlayMessage(&message);
}

static void __attribute__((unused)) startRealtimeServerIfNeeded(void) {
    if (!gIsSpringBoardProcess || gRealtimeServerSocket) {
        return;
    }

    unlink(kOverlayRealtimeSocketPath);

    CFSocketContext context = {0, NULL, NULL, NULL, NULL};
    gRealtimeServerSocket = CFSocketCreate(kCFAllocatorDefault,
                                           PF_LOCAL,
                                           SOCK_DGRAM,
                                           0,
                                           kCFSocketDataCallBack,
                                           realtimeSocketCallback,
                                           &context);
    if (!gRealtimeServerSocket) {
        NSLog(@"[OverlayIOSTOOL] Failed to create realtime socket");
        return;
    }

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, kOverlayRealtimeSocketPath, sizeof(address.sun_path));

    NSData *addressData = [NSData dataWithBytes:&address length:sizeof(address)];
    if (CFSocketSetAddress(gRealtimeServerSocket, (__bridge CFDataRef)addressData) != kCFSocketSuccess) {
        NSLog(@"[OverlayIOSTOOL] Failed to bind realtime socket");
        CFRelease(gRealtimeServerSocket);
        gRealtimeServerSocket = NULL;
        unlink(kOverlayRealtimeSocketPath);
        return;
    }

    chmod(kOverlayRealtimeSocketPath, 0666);
    gRealtimeServerSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, gRealtimeServerSocket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), gRealtimeServerSource, kCFRunLoopCommonModes);
    NSLog(@"[OverlayIOSTOOL] Realtime socket ready");
}

static void sendRealtimeOverlayState(void) {
    if (gIsSpringBoardProcess || !gOverlayImageView || gApplyingRemoteState) {
        return;
    }

    if (gRealtimeClientSocket < 0) {
        gRealtimeClientSocket = socket(AF_UNIX, SOCK_DGRAM, 0);
        if (gRealtimeClientSocket < 0) {
            return;
        }
    }

    CGRect frame = gOverlayImageView.frame;
    OverlayRealtimeMessage message = {
        .magic = kOverlayRealtimeMagic,
        .version = 1,
        .kind = 1,
        .x = frame.origin.x,
        .y = frame.origin.y,
        .width = frame.size.width,
        .height = frame.size.height,
        .dimOpacity = gDimOpacity,
        .dimAnimationMs = gDimAnimationMs,
        .visible = gOverlayVisible ? 1 : 0,
        .dimmed = gOverlayDimmed ? 1 : 0,
        .scaleLock = gScaleLockModeEnabled ? 1 : 0
    };

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, kOverlayRealtimeSocketPath, sizeof(address.sun_path));

    ssize_t sent = sendto(gRealtimeClientSocket,
                          &message,
                          sizeof(message),
                          0,
                          (struct sockaddr *)&address,
                          sizeof(address));
    if (sent < 0) {
        close(gRealtimeClientSocket);
        gRealtimeClientSocket = -1;
    }
}

static void syncOverlayStateRealtime(BOOL force) {
    if (!gOverlayImageView || gApplyingRemoteState) {
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (!force && now - gLastRealtimeStateSync < (1.0 / 60.0)) {
        return;
    }

    gLastRealtimeStateSync = now;
    sendRealtimeOverlayState();
    if (force) {
        persistOverlayState(YES);
    }
}

static CGRect frameFromOverlayStateKey(NSDictionary *state, NSString *key) {
    NSDictionary *frameState = state[key];
    if (![frameState isKindOfClass:NSDictionary.class]) {
        return CGRectNull;
    }

    CGFloat x = [frameState[@"x"] doubleValue];
    CGFloat y = [frameState[@"y"] doubleValue];
    CGFloat w = [frameState[@"w"] doubleValue];
    CGFloat h = [frameState[@"h"] doubleValue];
    if (w < 2 || h < 2) {
        return CGRectNull;
    }

    return CGRectMake(x, y, w, h);
}

static CGRect frameFromOverlayState(NSDictionary *state) {
    return frameFromOverlayStateKey(state, @"frame");
}

