import { image } from '@kit.ImageKit';
import { display, KeyboardAvoidMode, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { connect, freerdpVersion, getFrame, getSessionInfo, sendKey, sendMouse, sendMouseMove, sendUnicode, sendWheel, stopSession, version } from 'liblanrdp.so';

interface ComboKey {
  code: number;
  extended: boolean;
}

interface ModifierInfo {
  scan: number;
  extended: boolean;
}

interface DesktopSize {
  width: number;
  height: number;
}

interface ScaleValues {
  desktop: number;
  device: number;
}

interface SavedConnection {
  id: string;
  name?: string;
  host: string;
  port: string;
  username: string;
  domain: string;
  resolutionPreset: number;
  scalePreset?: number;
  savePassword: boolean;
}

@Entry
@Component
struct Index {
  @State private host: string = '';
  @State private portText: string = '3389';
  @State private username: string = '';
  @State private password: string = '';
  @State private domain: string = '';
  @State private resolutionPreset: number = 0;
  @State private scalePreset: number = 0;
  @State private savePassword: boolean = false;
  @State private savedConnections: SavedConnection[] = [];
  @State private selectedConnectionIndex: number = 0;
  @State private selectedConnectionId: string = '';
  @State private renamingProfile: boolean = false;
  @State private renameText: string = '';
  private loadingSettings: boolean = false;
  private applyingProfile: boolean = false;
  @State private status: string = `FreeRDP ${freerdpVersion()}`;
  @State private isConnecting: boolean = false;
  @State private connected: boolean = false;
  @State private frameImage: image.PixelMap | null = null;
  @State private frameVersion: number = 0;
  @State private frameWidth: number = 0;
  @State private frameHeight: number = 0;
  @State private imageViewWidth: number = 0;
  @State private imageViewHeight: number = 0;
  @State private mouseButton: number = 1;
  @State private keyboardText: string = '';
  @State private keyboardVisible: boolean = false;
  @State private shiftActive: boolean = false;
  @State private shiftLatch: boolean = false;
  @State private shiftCompat: boolean = true;
  @State private ctrlActive: boolean = false;
  @State private altActive: boolean = false;
  @State private comboActive: boolean = false;
  @State private moveMode: boolean = false;
  @State private keyStyle: number = 0;
  @State private inputFocused: boolean = false;
  @State private viewOffsetY: number = 0;
  @State private viewScale: number = 1;
  @State private systemKeyboardHeight: number = 0;
  @State private virtualKeyboardHeight: number = 0;
  private comboKeys: ComboKey[] = [];
  private heldModifiers: number[] = [];
  private appWindow: window.Window | null = null;
  private panLastY: number = 0;
  private panMoved: boolean = false;
  private pinchStartScale: number = 1;
  private imageGlobalX: number = 0;
  private imageGlobalY: number = 0;
  private touchStartTime: number = 0;
  private lastClickY: number = 0;
  private shiftHeld: boolean = false;
  private shiftUsed: boolean = false;
  private shiftScan: number = 0x2A;
  private shiftDownAt: number = 0;
  private shiftGrace: boolean = false;
  private shiftGraceTimer: number = -1;
  private mouseDown: boolean = false;
  private timer: number = -1;
  private frameBusy: boolean = false;
  private sessionEpoch: number = 0;
  private longPressTimer: number = -1;
  private longPressTriggered: boolean = false;
  private touchMoved: boolean = false;
  private lastTouchX: number = 0;
  private lastTouchY: number = 0;
  private lastWheelY: number = -1;
  private lastPanOffsetY: number = 0;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      this.appWindow = win;
      win.on('keyboardHeightChange', (height: number) => {
        console.info(`LanRDP keyboardHeight ${height}`);
        this.systemKeyboardHeight = height;
      });
    });
    this.loadSavedSettings();
  }

  onPageShow(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    if (this.connected) {
      setTimeout(() => {
        this.focusRemoteKeyboard();
      }, 50);
    }
  }

  aboutToDisappear(): void {
    if (this.appWindow !== null) {
      this.appWindow.off('keyboardHeightChange');
      this.appWindow = null;
    }
    this.stopFrameTimer();
    this.releaseModifiers("disappear");
    stopSession();
  }

  private cancelLongPress(): void {
    if (this.longPressTimer >= 0) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = -1;
    }
  }

  private stopFrameTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private focusRemoteKeyboard(): void {
    try {
      this.getUIContext().getFocusController().requestFocus('remoteKeyboard');
    } catch (error) {
      console.error(`LanRDP focus failed: ${String(error)}`);
    }
  }

  private resolutionLabel(): string {
    const labels: string[] = [
      '自动（推荐）', '1024×768', '1280×800', '1440×900', '1600×900', '1920×1080'
    ];
    if (this.resolutionPreset >= 0 && this.resolutionPreset < labels.length) {
      return labels[this.resolutionPreset];
    }
    return labels[0];
  }

  private resolutionSize(): DesktopSize {
    const presets: DesktopSize[] = [
      { width: 0, height: 0 },
      { width: 1024, height: 768 },
      { width: 1280, height: 800 },
      { width: 1440, height: 900 },
      { width: 1600, height: 900 },
      { width: 1920, height: 1080 }
    ];
    if (this.resolutionPreset > 0 && this.resolutionPreset < presets.length) {
      return presets[this.resolutionPreset];
    }

    let width = 1280;
    let height = 800;
    try {
      const info = display.getDefaultDisplaySync();
      const viewWidth = Math.floor(px2vp(info.width));
      const viewHeight = Math.floor(px2vp(info.height));
      width = Math.floor((viewWidth - 16) / 8) * 8;
      height = Math.floor((viewHeight - 140) / 8) * 8;
    } catch (error) {
      console.info(`LanRDP display size failed: ${String(error)}`);
    }
    if (width < 800) width = 800;
    if (width > 1920) width = 1920;
    if (height < 600) height = 600;
    if (height > 1200) height = 1200;
    return { width: width, height: height };
  }

  private scaleLabel(): string {
    const labels: string[] = ['100%（推荐）', '125%', '150%', '175%', '200%'];
    if (this.scalePreset >= 0 && this.scalePreset < labels.length) {
      return labels[this.scalePreset];
    }
    return labels[0];
  }

  private scaleValues(): ScaleValues {
    const scales: ScaleValues[] = [
      { desktop: 100, device: 100 },
      { desktop: 125, device: 140 },
      { desktop: 150, device: 140 },
      { desktop: 175, device: 180 },
      { desktop: 200, device: 180 }
    ];
    if (this.scalePreset >= 0 && this.scalePreset < scales.length) {
      return scales[this.scalePreset];
    }
    return scales[0];
  }

  private scalePercent(): string {
    return `${this.scaleValues().desktop}%`;
  }

  private passwordAlias(id: string = 'default'): Uint8Array {
    const name = id === 'default'
      ? 'com.xiaodaoatwc.lanrdp.password'
      : `com.xiaodaoatwc.lanrdp.password.${id}`;
    return new util.TextEncoder().encodeInto(name);
  }

  private async getPref(): Promise<preferences.Preferences | null> {
    const context = this.getUIContext().getHostContext();
    if (!context) {
      return null;
    }
    return await preferences.getPreferences(context, 'lanrdp');
  }

  private async loadSavedSettings(): Promise<void> {
    this.loadingSettings = true;
    try {
      const pref = await this.getPref();
      if (!pref) {
        return;
      }
      const host = String(await pref.get('host', ''));
      const port = String(await pref.get('port', '3389'));
      const username = String(await pref.get('username', ''));
      const domain = String(await pref.get('domain', ''));
      const resolution = Number(await pref.get('resolution', 0));
      const scale = Number(await pref.get('scale', 0));
      const remember = Boolean(await pref.get('savePassword', false));
      const rawProfiles = String(await pref.get('connections', ''));
      if (rawProfiles.length > 0) {
        try {
          const parsed = JSON.parse(rawProfiles) as SavedConnection[];
          if (Array.isArray(parsed)) {
            this.savedConnections = parsed;
            this.selectedConnectionIndex = 0;
          }
        } catch (error) {
          console.info(`LanRDP parse profiles failed: ${String(error)}`);
        }
      }
      if (this.host.length === 0) {
        this.host = host;
        this.portText = port.length > 0 ? port : '3389';
        this.username = username;
        this.domain = domain;
      }
      if (resolution >= 0 && resolution <= 5) {
        this.resolutionPreset = resolution;
      }
      if (scale >= 0 && scale < 5) {
        this.scalePreset = scale;
      }
      this.savePassword = remember;
      if (remember) {
        const password = await this.loadSavedPassword();
        if (password.length > 0) {
          this.password = password;
        } else {
          this.savePassword = false;
        }
      }
      console.info('LanRDP settings loaded');
    } catch (error) {
      console.info(`LanRDP load settings failed: ${String(error)}`);
    } finally {
      this.loadingSettings = false;
    }
  }

  private async saveConnectionSettings(): Promise<void> {
    if (this.loadingSettings) {
      return;
    }
    try {
      const pref = await this.getPref();
      if (!pref) {
        return;
      }
      await pref.put('host', this.host.trim());
      await pref.put('port', this.portText.trim());
      await pref.put('username', this.username.trim());
      await pref.put('domain', this.domain.trim());
      await pref.put('resolution', this.resolutionPreset);
      await pref.put('scale', this.scalePreset);
      await pref.put('savePassword', this.savePassword);
      await pref.flush();
      if (this.savePassword) {
        await this.savePasswordToAsset(this.password);
      } else {
        await this.removeSavedPassword();
      }
      console.info('LanRDP settings saved');
    } catch (error) {
      console.info(`LanRDP save settings failed: ${String(error)}`);
    }
  }

  private async savePasswordToAsset(password: string, id: string = 'default'): Promise<void> {
    if (password.length === 0) {
      await this.removeSavedPassword(id);
      return;
    }
    const alias = this.passwordAlias(id);
    const secret = new util.TextEncoder().encodeInto(password);
    const query = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, alias);
    try {
      await asset.remove(query);
    } catch (error) {
      console.info(`LanRDP asset remove before add: ${String(error)}`);
    }

    const attributes = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, alias);
    attributes.set(asset.Tag.SECRET, secret);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.IS_PERSISTENT, true);
    try {
      await asset.add(attributes);
      console.info('LanRDP password saved to Asset Store');
    } catch (error) {
      console.info(`LanRDP asset add failed: ${String(error)}`);
      attributes.delete(asset.Tag.IS_PERSISTENT);
      try {
        await asset.add(attributes);
        console.info('LanRDP password saved to Asset Store (non-persistent)');
      } catch (retryError) {
        console.info(`LanRDP asset add retry failed: ${String(retryError)}`);
      }
    }
  }

  private async loadSavedPassword(id: string = 'default'): Promise<string> {
    try {
      const query = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, this.passwordAlias(id));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const results = await asset.query(query);
      if (results.length === 0) {
        return '';
      }
      const value = results[0].get(asset.Tag.SECRET);
      if (value instanceof Uint8Array) {
        return new util.TextDecoder().decodeToString(value);
      }
    } catch (error) {
      console.info(`LanRDP load password failed: ${String(error)}`);
    }
    return '';
  }

  private async removeSavedPassword(id: string = 'default'): Promise<void> {
    try {
      const query = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, this.passwordAlias(id));
      await asset.remove(query);
      console.info('LanRDP saved password removed');
    } catch (error) {
      console.info(`LanRDP remove password: ${String(error)}`);
    }
  }

  private connectionLabel(profile: SavedConnection): string {
    if (profile.name !== undefined && profile.name.length > 0) {
      return profile.name;
    }
    const name = profile.username.length > 0 ? `${profile.username}@${profile.host}` : profile.host;
    return profile.port.length > 0 && profile.port !== '3389' ? `${name}:${profile.port}` : name;
  }

  private startRename(): void {
    if (this.selectedConnectionId.length === 0) {
      this.status = '请先选择连接记录';
      return;
    }
    const profile = this.savedConnections.find((item: SavedConnection) => item.id === this.selectedConnectionId);
    if (!profile) {
      return;
    }
    this.renameText = profile.name !== undefined && profile.name.length > 0
      ? profile.name
      : this.connectionLabel(profile);
    this.renamingProfile = true;
  }

  private async confirmRename(): Promise<void> {
    const id = this.selectedConnectionId;
    const index = this.savedConnections.findIndex((item: SavedConnection) => item.id === id);
    if (index < 0) {
      this.renamingProfile = false;
      return;
    }
    const old = this.savedConnections[index];
    const next = this.savedConnections.slice();
    next[index] = {
      id: old.id,
      name: this.renameText.trim(),
      host: old.host,
      port: old.port,
      username: old.username,
      domain: old.domain,
      resolutionPreset: old.resolutionPreset,
      scalePreset: old.scalePreset,
      savePassword: old.savePassword
    };
    this.savedConnections = next;
    this.renamingProfile = false;
    await this.persistProfiles();
    this.status = '已重命名连接记录';
  }

  private cancelRename(): void {
    this.renamingProfile = false;
    this.renameText = '';
  }

  private connectionOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '手动输入' }];
    for (let i = 0; i < this.savedConnections.length; i++) {
      options.push({ value: this.connectionLabel(this.savedConnections[i]) });
    }
    return options;
  }

  private selectedConnectionLabel(): string {
    if (this.selectedConnectionIndex <= 0 || this.selectedConnectionIndex > this.savedConnections.length) {
      return '手动输入';
    }
    return this.connectionLabel(this.savedConnections[this.selectedConnectionIndex - 1]);
  }

  private async applyProfile(profile: SavedConnection): Promise<void> {
    this.applyingProfile = true;
    try {
      this.selectedConnectionId = profile.id;
      this.host = profile.host;
      this.portText = profile.port.length > 0 ? profile.port : '3389';
      this.username = profile.username;
      this.domain = profile.domain;
      this.resolutionPreset = profile.resolutionPreset;
      this.scalePreset = profile.scalePreset !== undefined ? profile.scalePreset : 0;
      this.savePassword = profile.savePassword;
      this.password = '';
      if (profile.savePassword) {
        const saved = await this.loadSavedPassword(profile.id);
        if (saved.length > 0) {
          this.password = saved;
        }
      }
      this.status = '已载入连接记录';
    } finally {
      this.applyingProfile = false;
    }
  }

  private async persistProfiles(): Promise<void> {
    try {
      const pref = await this.getPref();
      if (!pref) {
        return;
      }
      await pref.put('connections', JSON.stringify(this.savedConnections));
      await pref.flush();
    } catch (error) {
      console.info(`LanRDP save profiles failed: ${String(error)}`);
    }
  }

  private async saveCurrentProfile(showStatus: boolean = false): Promise<void> {
    const host = this.host.trim();
    if (host.length === 0) {
      if (showStatus) {
        this.status = '请输入主机名或 IP';
      }
      return;
    }

    let id = this.selectedConnectionId;
    let index = id.length > 0
      ? this.savedConnections.findIndex((item: SavedConnection) => item.id === id)
      : -1;
    if (index < 0) {
      const match = this.savedConnections.findIndex((item: SavedConnection) =>
        item.host === host &&
        item.port === this.portText.trim() &&
        item.username === this.username.trim() &&
        item.domain === this.domain.trim());
      if (match >= 0) {
        index = match;
        id = this.savedConnections[match].id;
      }
    }
    if (id.length === 0) {
      id = util.generateRandomUUID();
    }

    const existingName = index >= 0 ? this.savedConnections[index].name : undefined;
    const profile: SavedConnection = {
      id: id,
      name: existingName,
      host: host,
      port: this.portText.trim(),
      username: this.username.trim(),
      domain: this.domain.trim(),
      resolutionPreset: this.resolutionPreset,
      scalePreset: this.scalePreset,
      savePassword: this.savePassword
    };
    const next = this.savedConnections.slice();
    if (index >= 0) {
      next[index] = profile;
    } else {
      next.push(profile);
      index = next.length - 1;
    }
    this.savedConnections = next;
    this.selectedConnectionId = id;
    this.selectedConnectionIndex = index + 1;
    await this.persistProfiles();
    if (this.savePassword) {
      await this.savePasswordToAsset(this.password, id);
    } else {
      await this.removeSavedPassword(id);
    }
    if (showStatus) {
      this.status = '已保存连接记录';
    }
    console.info(`LanRDP profile saved id=${id} count=${next.length}`);
  }

  private async deleteSelectedProfile(): Promise<void> {
    const id = this.selectedConnectionId;
    if (id.length === 0) {
      this.status = '请先选择连接记录';
      return;
    }
    this.savedConnections = this.savedConnections.filter((item: SavedConnection) => item.id !== id);
    this.selectedConnectionId = '';
    this.selectedConnectionIndex = 0;
    await this.removeSavedPassword(id);
    await this.persistProfiles();
    this.status = '已删除连接记录';
  }

  private async doConnect(): Promise<void> {
    const host = this.host.trim();
    const port = Number(this.portText);

    if (host.length === 0) {
      this.status = '请输入主机名或 IP';
      return;
    }
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      this.status = '端口必须在 1–65535 之间';
      return;
    }

    this.stopFrameTimer();
    this.releaseModifiers("connect");
    this.shiftLatch = false;
    this.inputFocused = false;
    stopSession();
    this.sessionEpoch++;
    this.frameBusy = false;
    this.frameImage?.release();
    this.frameImage = null;
    this.frameVersion = 0;
    this.isConnecting = true;
    this.status = '连接中…';
    const desktop = this.resolutionSize();
    const scale = this.scaleValues();

    try {
      const result = await connect(
        host,
        port,
        this.username.trim(),
        this.password,
        this.domain.trim(),
        desktop.width,
        desktop.height,
        scale.desktop,
        scale.device
      );
      if (result === 'connected') {
        this.connected = true;
        this.status = '连接成功，等待画面…';
        setTimeout(() => {
          this.focusRemoteKeyboard();
        }, 50);
        this.timer = setInterval(() => {
          this.refreshFrame();
        }, 200);
        this.saveConnectionSettings();
        this.saveCurrentProfile();
      } else {
        this.status = result;
      }
    } catch (error) {
      this.status = `连接失败：${String(error)}`;
    } finally {
      this.isConnecting = false;
    }
  }

  private async refreshFrame(): Promise<void> {
    if (this.isConnecting || this.frameBusy) {
      return;
    }
    const info = getSessionInfo();
    if (info.state === 3 || info.state === 4) {
      this.onSessionLost(info.error);
      return;
    }
    if (info.state === 0 && this.connected) {
      this.onSessionLost('会话已结束');
      return;
    }
    if (info.state !== 2) {
      return;
    }
    if (info.version === this.frameVersion && this.frameImage !== null) {
      return;
    }

    this.frameBusy = true;
    const epoch = this.sessionEpoch;
    try {
      const frame = getFrame();
      if (!frame) {
        return;
      }
      if (frame.version === this.frameVersion && this.frameImage !== null) {
        return;
      }
      const options: image.InitializationOptions = {
        size: { width: frame.width, height: frame.height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false,
        alphaType: image.AlphaType.OPAQUE
      };
      const pixelMap = await image.createPixelMap(frame.data, options);
      if (epoch !== this.sessionEpoch) {
        pixelMap.release();
        return;
      }
      const after = getSessionInfo();
      if (after.state !== 2) {
        pixelMap.release();
        this.onSessionLost(after.error);
        return;
      }
      const old = this.frameImage;
      this.frameImage = pixelMap;
      this.frameVersion = frame.version;
      this.frameWidth = frame.width;
      this.frameHeight = frame.height;
      this.status = `已连接 · ${frame.width}×${frame.height} · ${this.scalePercent()}`;
      old?.release();
    } catch (error) {
      this.status = `渲染失败：${String(error)}`;
    } finally {
      this.frameBusy = false;
    }
  }

  private onSessionLost(error: string): void {
    if (!this.connected) {
      return;
    }
    console.info(`LanRDP session lost: ${error}`);
    this.stopFrameTimer();
    this.releaseModifiers('sessionLost');
    this.sessionEpoch++;
    this.frameBusy = false;
    this.frameImage?.release();
    this.frameImage = null;
    this.frameVersion = 0;
    this.connected = false;
    this.inputFocused = false;
    this.mouseDown = false;
    this.longPressTriggered = false;
    this.viewScale = 1;
    this.viewOffsetY = 0;
    const detail = error.length > 120 ? error.substring(0, 120) : error;
    this.status = detail.length > 0 ? `连接已断开：${detail}` : '连接已断开';
  }

  private handleTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      this.cancelLongPress();
      if (this.mouseDown && !this.longPressTriggered) {
        this.sendMouseAt(this.lastTouchX, this.lastTouchY, false);
      }
      this.mouseDown = false;
      this.longPressTriggered = false;
      this.lastWheelY = -1;
      return;
    }

    const touch = event.touches[0];
    const touchX = touch.windowX - this.imageGlobalX;
    const touchY = touch.windowY - this.imageGlobalY;
    if (this.moveMode) {
      if (event.type === TouchType.Down) {
        this.panLastY = touchY;
        this.panMoved = false;
      } else if (event.type === TouchType.Move) {
        const delta = touchY - this.panLastY;
        if (Math.abs(delta) > 4) {
          this.panMoved = true;
        }
        this.viewOffsetY = Math.max(-this.imageViewHeight * 0.45, Math.min(0, this.viewOffsetY + delta));
        this.panLastY = touchY;
      }
      return;
    }
    const previousX = this.lastTouchX;
    const previousY = this.lastTouchY;
    this.lastTouchX = touchX;
    this.lastTouchY = touchY;

    if (event.touches.length >= 2) {
      this.cancelLongPress();
      if (this.mouseDown) {
        this.sendMouseAt(this.lastTouchX, this.lastTouchY, false, 1);
        this.mouseDown = false;
      }
      const second = event.touches[1];
      const secondY = second.windowY - this.imageGlobalY;
      const averageY = (touchY + secondY) / 2;
      if (this.lastWheelY >= 0 && Math.abs(averageY - this.lastWheelY) >= 12) {
        sendWheel(averageY < this.lastWheelY ? 120 : -120);
        this.lastWheelY = averageY;
      } else if (this.lastWheelY < 0) {
        this.lastWheelY = averageY;
      }
      return;
    }

    if (event.type === TouchType.Down) {
      if (!this.keyboardVisible) {
        this.inputFocused = false;
        this.focusRemoteKeyboard();
      }
      this.lastWheelY = -1;
      this.lastClickY = touchY;
      this.mouseDown = true;
      this.touchMoved = false;
      this.longPressTriggered = false;
      this.touchStartTime = Date.now();
      this.sendMouseAt(touchX, touchY, true);

      this.cancelLongPress();
      this.longPressTimer = setTimeout(() => {
        if (this.mouseDown && !this.touchMoved && !this.longPressTriggered) {
          this.sendMouseAt(this.lastTouchX, this.lastTouchY, false, 1);
          this.sendMouseAt(this.lastTouchX, this.lastTouchY, true, 2);
          this.sendMouseAt(this.lastTouchX, this.lastTouchY, false, 2);
          this.longPressTriggered = true;
        }
      }, 550);
    } else if (event.type === TouchType.Move && this.mouseDown) {
      if (Math.abs(touchX - previousX) > 6 || Math.abs(touchY - previousY) > 6) {
        this.touchMoved = true;
      }
      if (this.touchMoved) {
        this.cancelLongPress();
      }
      if (!this.longPressTriggered) {
        this.sendMouseMoveAt(touchX, touchY, this.mouseButton);
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.cancelLongPress();
      const held = Date.now() - this.touchStartTime;
      if (!this.longPressTriggered && held > 550 && !this.touchMoved) {
        this.sendMouseAt(touchX, touchY, false, 1);
        this.sendMouseAt(touchX, touchY, true, 2);
        this.sendMouseAt(touchX, touchY, false, 2);
      } else if (!this.longPressTriggered) {
        this.sendMouseAt(touchX, touchY, false);
      }
      this.mouseDown = false;
      this.longPressTriggered = false;
      this.lastWheelY = -1;
    }
  }

  private sendMouseAt(x: number, y: number, down: boolean, button?: number): void {
    if (this.frameWidth <= 0 || this.frameHeight <= 0 ||
        this.imageViewWidth <= 0 || this.imageViewHeight <= 0) {
      return;
    }
    const scale = Math.min(this.imageViewWidth / this.frameWidth, this.imageViewHeight / this.frameHeight);
    const drawWidth = this.frameWidth * scale;
    const drawHeight = this.frameHeight * scale;
    const left = (this.imageViewWidth - drawWidth) / 2;
    const top = (this.imageViewHeight - drawHeight) / 2;
    if (x < left || y < top || x >= left + drawWidth || y >= top + drawHeight) {
      return;
    }
    const scaledX = (x - this.imageViewWidth / 2) / this.viewScale + this.imageViewWidth / 2;
    const scaledY = (y - this.imageViewHeight / 2) / this.viewScale + this.imageViewHeight / 2;
    const remoteX = Math.floor((scaledX - left) / scale);
    const remoteY = Math.floor((scaledY - this.viewOffsetY - top) / scale);
    sendMouse(remoteX, remoteY, button ?? this.mouseButton, down);
  }

  private tapKey(code: number, extended: boolean = false): void {
    sendKey(code, true, extended);
    sendKey(code, false, extended);
  }

  private modifierInfo(code: number): ModifierInfo | null {
    if (code === 2047) { return { scan: 0x2A, extended: false }; }
    if (code === 2048) { return { scan: 0x36, extended: false }; }
    if (code === 2045) { return { scan: 0x38, extended: false }; }
    if (code === 2046) { return { scan: 0x38, extended: true }; }
    if (code === 2072) { return { scan: 0x1D, extended: false }; }
    if (code === 2073) { return { scan: 0x1D, extended: true }; }
    if (code === 2076) { return { scan: 0x5B, extended: true }; }
    if (code === 2077) { return { scan: 0x5C, extended: true }; }
    return null;
  }

  private modifierName(code: number): string {
    if (code === 2047 || code === 2048) { return 'Shift'; }
    if (code === 2045 || code === 2046) { return 'Alt'; }
    if (code === 2072 || code === 2073) { return 'Ctrl'; }
    return '';
  }

  private hasNonShiftModifier(): boolean {
    return this.heldModifiers.indexOf(2045) >= 0 ||
      this.heldModifiers.indexOf(2046) >= 0 ||
      this.heldModifiers.indexOf(2072) >= 0 ||
      this.heldModifiers.indexOf(2073) >= 0 ||
      this.heldModifiers.indexOf(2076) >= 0 ||
      this.heldModifiers.indexOf(2077) >= 0;
  }

  private cancelShiftGrace(): void {
    if (this.shiftGraceTimer >= 0) {
      clearTimeout(this.shiftGraceTimer);
      this.shiftGraceTimer = -1;
    }
    this.shiftGrace = false;
  }

  private startShiftGrace(): void {
    this.cancelShiftGrace();
    this.shiftGrace = true;
    console.info('LanRDP shift grace start');
    this.shiftGraceTimer = setTimeout(() => {
      this.shiftGraceTimer = -1;
      if (this.shiftGrace) {
        this.shiftGrace = false;
        console.info('LanRDP shift grace timeout -> tap');
        this.sendShiftTap();
      }
    }, 350);
  }

  private sendShiftTap(): void {
    sendKey(0x2A, true, false);
    setTimeout(() => {
      sendKey(0x2A, false, false);
    }, 100);
  }

  private sendKeyWithShift(code: number, extended: boolean = false): void {
    sendKey(this.shiftScan, true, false);
    sendKey(code, true, extended);
    sendKey(code, false, extended);
    sendKey(this.shiftScan, false, false);
    this.shiftUsed = true;
  }

  private tapSpecial(code: number, extended: boolean = false): void {
    if (this.shiftCompat && (this.shiftHeld || this.shiftGrace)) {
      console.info(`LanRDP shifted special code=${code} via=${this.shiftGrace ? 'grace' : 'held'}`);
      this.cancelShiftGrace();
      this.sendKeyWithShift(code, extended);
      return;
    }
    this.tapKey(code, extended);
  }

  private tapText(code: number, extended: boolean, shiftChar: string): void {
    if (this.shiftCompat && (this.shiftHeld || this.shiftGrace)) {
      console.info(`LanRDP shifted text '${shiftChar}' via=${this.shiftGrace ? 'grace' : 'held'}`);
      this.cancelShiftGrace();
      if (!this.hasNonShiftModifier() && shiftChar.length === 1) {
        sendUnicode(shiftChar.charCodeAt(0), true);
        sendUnicode(shiftChar.charCodeAt(0), false);
        this.shiftUsed = true;
        return;
      }
      this.sendKeyWithShift(code, extended);
      return;
    }
    this.tapKey(code, extended);
  }

  private handleModifier(code: number, down: boolean): void {
    const info = this.modifierInfo(code);
    if (info === null) {
      return;
    }
    if (this.shiftCompat && (code === 2047 || code === 2048)) {
      if (down) {
        if (this.shiftHeld) {
          return;
        }
        this.cancelShiftGrace();
        this.shiftHeld = true;
        this.shiftUsed = false;
        this.shiftLatch = false;
        this.shiftScan = code === 2048 ? 0x36 : 0x2A;
        this.shiftDownAt = Date.now();
        console.info(`LanRDP compat shift down scan=${this.shiftScan}`);
      } else {
        if (!this.shiftHeld) {
          return;
        }
        this.shiftHeld = false;
        const heldMs = Date.now() - this.shiftDownAt;
        console.info(`LanRDP compat shift up heldMs=${heldMs} used=${this.shiftUsed}`);
        if (!this.shiftUsed) {
          if (heldMs < 80) {
            this.startShiftGrace();
          } else {
            this.sendShiftTap();
          }
        }
        this.shiftUsed = false;
      }
      return;
    }
    const index = this.heldModifiers.indexOf(code);
    if (down) {
      if (index >= 0) {
        return;
      }
      this.heldModifiers.push(code);
      sendKey(info.scan, true, info.extended);
      console.info(`LanRDP native modifier down code=${code} scan=${info.scan}`);
    } else {
      if (index < 0) {
        return;
      }
      this.heldModifiers.splice(index, 1);
      sendKey(info.scan, false, info.extended);
      console.info(`LanRDP native modifier up code=${code} scan=${info.scan}`);
    }
    if (code === 2047 || code === 2048) {
      this.shiftHeld = this.heldModifiers.indexOf(2047) >= 0 ||
        this.heldModifiers.indexOf(2048) >= 0;
      if (down) {
        this.shiftLatch = false;
      }
    }
  }

  private releaseModifiers(reason: string = ''): void {
    console.info(`LanRDP release reason=${reason} held=${this.heldModifiers.join(',')} shiftHeld=${this.shiftHeld} compat=${this.shiftCompat}`);
    this.cancelShiftGrace();
    for (let i = 0; i < this.heldModifiers.length; i++) {
      const info = this.modifierInfo(this.heldModifiers[i]);
      if (info !== null) {
        sendKey(info.scan, false, info.extended);
      }
    }
    this.heldModifiers = [];
    this.shiftHeld = false;
    this.shiftUsed = false;
    this.shiftLatch = false;
  }

  private toggleShiftMode(): void {
    this.releaseModifiers('shiftMode');
    this.shiftCompat = !this.shiftCompat;
    this.shiftHeld = false;
    this.shiftUsed = false;
    this.shiftLatch = false;
    this.status = this.shiftCompat
      ? 'Shift 兼容：字母不触发输入法切换'
      : 'Shift 原生：由 Windows 处理';
    console.info(`LanRDP shift mode compat=${this.shiftCompat}`);
  }

  private toggleRemoteIME(): void {
    this.cancelShiftGrace();
    this.shiftLatch = false;
    this.inputFocused = false;
    this.focusRemoteKeyboard();
    this.sendShiftTap();
    this.status = '已发送 Shift：切换中/英';
  }

  private handleHardwareKey(event: KeyEvent): void {
    event.stopPropagation();
    if (this.inputFocused) {
      return;
    }
    const code = event.keyCode;
    if (this.modifierInfo(code) !== null) {
      let physical = 'n/a';
      try {
        const name = this.modifierName(code);
        if (event.getModifierKeyState !== undefined && name.length > 0) {
          physical = String(event.getModifierKeyState([name]));
        }
      } catch (error) {
        physical = `err:${String(error)}`;
      }
      console.info(`LanRDP key code=${code} type=${event.type} compat=${this.shiftCompat} shiftHeld=${this.shiftHeld} held=${this.heldModifiers.join(',')} physical=${physical}`);
      this.handleModifier(code, event.type === KeyType.Down);
      return;
    }
    if (event.type !== KeyType.Down) {
      return;
    }
    if (code === 2074) { this.tapKey(0x3A); return; }
    if (code === 2054) { this.tapSpecial(0x1C); return; }
    if (code === 2055) { this.tapSpecial(0x0E); return; }
    if (code === 2070) { this.tapSpecial(0x01); return; }
    if (code === 2049) { this.tapSpecial(0x0F); return; }
    if (code === 2071) { this.tapSpecial(0x53, true); return; }
    if (code === 2012) { this.tapSpecial(0x48, true); return; }
    if (code === 2013) { this.tapSpecial(0x50, true); return; }
    if (code === 2014) { this.tapSpecial(0x4B, true); return; }
    if (code === 2015) { this.tapSpecial(0x4D, true); return; }
    if (code === 2050) { this.tapSpecial(0x39); return; }
    if (code === 2081) { this.tapSpecial(0x47, true); return; }
    if (code === 2082) { this.tapSpecial(0x4F, true); return; }
    if (code === 2083) { this.tapSpecial(0x52, true); return; }
    if (code === 2068) { this.tapSpecial(0x49, true); return; }
    if (code === 2069) { this.tapSpecial(0x51, true); return; }
    if (code >= 2090 && code <= 2101) {
      const functionKeys: number[] = [
        0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x57, 0x58
      ];
      this.tapSpecial(functionKeys[code - 2090]);
      return;
    }

    if (code >= 2017 && code <= 2042) {
      const letters: number[] = [
        0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17,
        0x24, 0x25, 0x26, 0x32, 0x31, 0x18, 0x19, 0x10, 0x13,
        0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C
      ];
      this.tapText(letters[code - 2017], false, String.fromCharCode(65 + (code - 2017)));
      return;
    }
    if (code >= 2000 && code <= 2009) {
      const digits: number[] = [0x0B, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A];
      this.tapText(digits[code - 2000], false, ')!@#$%^&*('.charAt(code - 2000));
      return;
    }
    if (code === 2043) { this.tapText(0x33, false, '<'); return; }
    if (code === 2044) { this.tapText(0x34, false, '>'); return; }
    if (code === 2064) { this.tapText(0x35, false, '?'); return; }
    if (code === 2057) { this.tapText(0x0C, false, '_'); return; }
    if (code === 2058) { this.tapText(0x0D, false, '+'); return; }
    if (code === 2059) { this.tapText(0x1A, false, '{'); return; }
    if (code === 2060) { this.tapText(0x1B, false, '}'); return; }
    if (code === 2061) { this.tapText(0x2B, false, '|'); return; }
    if (code === 2062) { this.tapText(0x27, false, ':'); return; }
    if (code === 2063) { this.tapText(0x28, false, '\"'); return; }
    if (code === 2056) { this.tapText(0x29, false, '~'); return; }

    const text = event.keyText;
    if (text.length === 1) {
      sendUnicode(text.charCodeAt(0), true);
      sendUnicode(text.charCodeAt(0), false);
      if (this.shiftCompat && this.shiftHeld) {
        this.shiftUsed = true;
      }
    }
  }

  private disconnect(): void {
    this.stopFrameTimer();
    this.releaseModifiers("disconnect");
    this.shiftLatch = false;
    stopSession();
    this.sessionEpoch++;
    this.frameBusy = false;
    this.frameImage?.release();
    this.frameImage = null;
    this.frameVersion = 0;
    this.viewScale = 1;
    this.viewOffsetY = 0;
    this.connected = false;
    this.mouseDown = false;
    this.longPressTriggered = false;
    this.inputFocused = false;
    this.status = '已断开';
  }

  private onInputFocus(): void {
    console.info('LanRDP input focus');
    this.releaseModifiers("inputFocus");
    this.inputFocused = true;
    this.keyboardVisible = false;
    this.adjustViewForInput();
  }

  private onInputBlur(): void {
    console.info('LanRDP input blur');
    this.inputFocused = false;
    this.viewOffsetY = 0;
  }

  private toggleVirtualKeyboard(): void {
    if (this.keyboardVisible) {
      this.keyboardVisible = false;
      this.viewOffsetY = 0;
      this.focusRemoteKeyboard();
      return;
    }
    this.releaseModifiers("virtualKeyboard");
    this.getUIContext().getFocusController().clearFocus();
    this.inputFocused = false;
    this.keyboardVisible = true;
    this.adjustViewForInput();
    setTimeout(() => {
      this.focusRemoteKeyboard();
    }, 50);
  }

  private sendMouseMoveAt(x: number, y: number, button?: number): void {
    if (this.frameWidth <= 0 || this.frameHeight <= 0 ||
        this.imageViewWidth <= 0 || this.imageViewHeight <= 0) {
      return;
    }
    const scale = Math.min(this.imageViewWidth / this.frameWidth, this.imageViewHeight / this.frameHeight);
    const drawWidth = this.frameWidth * scale;
    const drawHeight = this.frameHeight * scale;
    const left = (this.imageViewWidth - drawWidth) / 2;
    const top = (this.imageViewHeight - drawHeight) / 2;
    if (x < left || y < top || x >= left + drawWidth || y >= top + drawHeight) {
      return;
    }
    const scaledX = (x - this.imageViewWidth / 2) / this.viewScale + this.imageViewWidth / 2;
    const scaledY = (y - this.imageViewHeight / 2) / this.viewScale + this.imageViewHeight / 2;
    const remoteX = Math.floor((scaledX - left) / scale);
    const remoteY = Math.floor((scaledY - this.viewOffsetY - top) / scale);
    sendMouseMove(remoteX, remoteY, button ?? this.mouseButton);
  }

  private sendKeyboard(): void {
    const text = this.keyboardText;
    if (text.length === 0) {
      return;
    }
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i);
      sendUnicode(code, true);
      sendUnicode(code, false);
    }
    this.keyboardText = '';
  }

  private pressKey(code: number, extended: boolean = false, shiftChar?: string): void {
    this.cancelShiftGrace();
    if (this.comboActive) {
      sendKey(code, true, extended);
      this.comboKeys.push({ code: code, extended: extended });
      return;
    }
    if (this.shiftLatch) {
      if (this.shiftCompat && shiftChar !== undefined && shiftChar.length === 1) {
        sendUnicode(shiftChar.charCodeAt(0), true);
        sendUnicode(shiftChar.charCodeAt(0), false);
      } else {
        sendKey(0x2A, true, false);
        sendKey(code, true, extended);
        sendKey(code, false, extended);
        sendKey(0x2A, false, false);
      }
      this.shiftLatch = false;
      return;
    }
    sendKey(code, true, extended);
    sendKey(code, false, extended);
  }

  private toggleCombo(): void {
    if (!this.comboActive) {
      this.comboActive = true;
      this.comboKeys = [];
      this.shiftLatch = false;
      return;
    }
    for (let i = this.comboKeys.length - 1; i >= 0; i--) {
      const key = this.comboKeys[i];
      sendKey(key.code, false, key.extended);
    }
    this.comboKeys = [];
    this.comboActive = false;
    this.shiftLatch = false;
    this.shiftActive = false;
    this.ctrlActive = false;
    this.altActive = false;
  }

  private keyBg(): string {
    return this.keyStyle === 0 ? '#E5E7EB' : '#374151';
  }

  private keyFg(): string {
    return this.keyStyle === 0 ? '#111827' : '#F9FAFB';
  }

  @Builder
  Key(label: string, code: number, extended: boolean = false, weight: number = 1) {
    Button(label)
      .fontSize(11)
      .height(56)
      .padding(0)
      .borderRadius(4)
      .constraintSize({ minWidth: 0 })
      .layoutWeight(weight)
      .backgroundColor(this.keyBg())
      .fontColor(this.keyFg())
      .stateStyles({
        pressed: {
          .backgroundColor('#2563EB')
        }
      })
      .onClick(() => {
        this.pressKey(code, extended, label.length === 1 ? label : undefined);
      })
  }

  @Builder
  Key2(top: string, bottom: string, code: number, extended: boolean = false, weight: number = 1) {
    Button() {
      Column({ space: 0 }) {
        Text(top)
          .fontSize(9)
          .fontColor(this.keyFg())
        Text(bottom)
          .fontSize(12)
          .fontColor(this.keyFg())
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(56)
    .padding(0)
    .borderRadius(4)
    .constraintSize({ minWidth: 0 })
    .layoutWeight(weight)
    .backgroundColor(this.keyBg())
    .stateStyles({
      pressed: {
        .backgroundColor('#2563EB')
      }
    })
    .onClick(() => {
      this.pressKey(code, extended, top);
    })
  }

  @Builder
  NavKey(label: string, code: number, extended: boolean = false) {
    Button(label)
      .fontSize(11)
      .height(56)
      .width(72)
      .padding(0)
      .borderRadius(4)
      .backgroundColor(this.keyBg())
      .fontColor(this.keyFg())
      .stateStyles({
        pressed: {
          .backgroundColor('#2563EB')
        }
      })
      .onClick(() => {
        this.pressKey(code, extended);
      })
  }

  @Builder
  ModKey(label: string, code: number, active: boolean, extended: boolean = false, weight: number = 1) {
    Button(label)
      .fontSize(11)
      .height(56)
      .padding(0)
      .borderRadius(4)
      .constraintSize({ minWidth: 0 })
      .layoutWeight(weight)
      .backgroundColor(active ? '#2563EB' : this.keyBg())
      .fontColor(active ? '#FFFFFF' : this.keyFg())
      .stateStyles({
        pressed: {
          .backgroundColor('#2563EB')
        }
      })
      .onClick(() => {
        if (code === 0x2A && !this.comboActive) {
          this.shiftLatch = !this.shiftLatch;
          return;
        }
        if (this.comboActive) {
          sendKey(code, true, extended);
          this.comboKeys.push({ code: code, extended: extended });
          if (code === 0x2A) {
            this.shiftActive = true;
          } else if (code === 0x1D) {
            this.ctrlActive = true;
          } else if (code === 0x38) {
            this.altActive = true;
          }
        } else {
          sendKey(code, true, extended);
          sendKey(code, false, extended);
        }
      })
  }

  private adjustViewForInput(): void {
    if (this.lastClickY <= 0 || this.imageViewHeight <= 0) {
      return;
    }
    const keyboardHeight = this.imageViewHeight * 0.42;
    const visibleHeight = Math.max(80, this.imageViewHeight - keyboardHeight);
    if (this.lastClickY <= visibleHeight * 0.6) {
      this.viewOffsetY = 0;
      return;
    }
    const targetY = visibleHeight * 0.42;
    const desired = targetY - this.lastClickY;
    this.viewOffsetY = Math.max(-this.imageViewHeight * 0.45, Math.min(0, desired));
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 8 }) {
        if (!this.connected) {
          Text('LanRDP')
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .width('100%')
          Text('HarmonyOS NEXT · 远程桌面')
            .fontSize(13)
            .fontColor('#6B7280')
            .width('100%')

          Row({ space: 8 }) {
            Text('记录')
              .fontSize(13)
              .fontColor('#6B7280')
            Select(this.connectionOptions())
              .selected(this.selectedConnectionIndex)
              .value(this.selectedConnectionLabel())
              .font({ size: 13 })
              .layoutWeight(1)
              .onSelect((index: number, value: string) => {
                this.selectedConnectionIndex = index;
                if (index > 0 && index <= this.savedConnections.length) {
                  this.applyProfile(this.savedConnections[index - 1]);
                } else {
                  this.selectedConnectionId = '';
                }
              })
            Button('保存')
              .fontSize(12)
              .height(36)
              .onClick(() => {
                this.saveCurrentProfile(true);
              })
            Button('改名')
              .fontSize(12)
              .height(36)
              .onClick(() => {
                this.startRename();
              })
            Button('删除')
              .fontSize(12)
              .height(36)
              .onClick(() => {
                this.deleteSelectedProfile();
              })
          }
          .width('100%')

          if (this.renamingProfile) {
            Row({ space: 8 }) {
              TextInput({ placeholder: '连接名称', text: this.renameText })
                .onChange((value: string) => {
                  this.renameText = value;
                })
                .height(36)
                .layoutWeight(1)
              Button('确定')
                .fontSize(12)
                .height(36)
                .onClick(() => {
                  this.confirmRename();
                })
              Button('取消')
                .fontSize(12)
                .height(36)
                .onClick(() => {
                  this.cancelRename();
                })
            }
            .width('100%')
          }

          TextInput({ placeholder: '主机名或 IP，例如 192.0.2.10', text: this.host })
            .onChange((value: string) => {
              this.host = value;
            })
            .width('100%')

          Row({ space: 10 }) {
            TextInput({ placeholder: '端口', text: this.portText })
              .type(InputType.Number)
              .onChange((value: string) => {
                this.portText = value;
              })
              .layoutWeight(1)
            TextInput({ placeholder: '用户名', text: this.username })
              .onChange((value: string) => {
                this.username = value;
              })
              .layoutWeight(2)
          }
          .width('100%')

          Row({ space: 10 }) {
            TextInput({ placeholder: '密码', text: this.password })
              .type(InputType.Password)
              .onChange((value: string) => {
                this.password = value;
              })
              .layoutWeight(2)
            TextInput({ placeholder: '域（可选）', text: this.domain })
              .onChange((value: string) => {
                this.domain = value;
              })
              .layoutWeight(1)
          }
          .width('100%')

          Row({ space: 8 }) {
            Toggle({ type: ToggleType.Switch, isOn: this.savePassword })
              .onChange((isOn: boolean) => {
                this.savePassword = isOn;
                if (!this.loadingSettings && !this.applyingProfile) {
                  this.saveConnectionSettings();
                  if (this.selectedConnectionId.length > 0) {
                    this.saveCurrentProfile();
                  }
                }
              })
            Text('记住密码')
              .fontSize(13)
              .fontColor('#374151')
            Text('系统 Asset Store 加密保存')
              .fontSize(11)
              .fontColor('#9CA3AF')
              .layoutWeight(1)
          }
          .width('100%')

          Row({ space: 8 }) {
            Text('分辨率')
              .fontSize(13)
              .fontColor('#6B7280')
              .width(64)
            Select([
              { value: '自动（推荐）' },
              { value: '1024×768' },
              { value: '1280×800' },
              { value: '1440×900' },
              { value: '1600×900' },
              { value: '1920×1080' }
            ])
              .selected(this.resolutionPreset)
              .value(this.resolutionLabel())
              .font({ size: 13 })
              .layoutWeight(1)
              .onSelect((index: number, value: string) => {
                this.resolutionPreset = index;
              })
          }
          .width('100%')

          Row({ space: 8 }) {
            Text('缩放')
              .fontSize(13)
              .fontColor('#6B7280')
              .width(64)
            Select([
              { value: '100%（推荐）' },
              { value: '125%' },
              { value: '150%' },
              { value: '175%' },
              { value: '200%' }
            ])
              .selected(this.scalePreset)
              .value(this.scaleLabel())
              .font({ size: 13 })
              .layoutWeight(1)
              .onSelect((index: number, value: string) => {
                this.scalePreset = index;
              })
          }
          .width('100%')

          Button(this.isConnecting ? '连接中…' : '连接')
            .width('100%')
            .enabled(!this.isConnecting)
            .onClick(() => {
              this.doConnect();
            })

          Text(this.status)
            .fontSize(13)
            .fontColor(this.status.includes('失败') ? '#B91C1C' : '#6B7280')
            .width('100%')
        } else {
          Row({ space: 8 }) {
            Text(this.host)
              .fontSize(13)
              .fontColor('#6B7280')
              .layoutWeight(1)
            Text(this.status)
              .fontSize(12)
              .fontColor('#6B7280')
            Button('中/英')
              .fontSize(12)
              .onClick(() => {
                this.toggleRemoteIME();
              })
            Button(this.shiftCompat ? 'Shift兼容' : 'Shift原生')
              .fontSize(11)
              .onClick(() => {
                this.toggleShiftMode();
              })
            Button('键帽')
              .fontSize(12)
              .onClick(() => {
                this.keyStyle = (this.keyStyle + 1) % 2;
              })
            Button('断开')
              .fontSize(12)
              .onClick(() => {
                this.disconnect();
              })
          }
          .width('100%')
        }

        if (this.frameImage !== null) {
          Image(this.frameImage)
            .width('100%')
            .layoutWeight(1)
            .objectFit(ImageFit.Contain)
            .backgroundColor('#000000')
            .borderRadius(8)
            .translate({ y: this.viewOffsetY })
            .scale({ x: this.viewScale, y: this.viewScale })
            .onAreaChange((_oldValue: Area, newValue: Area) => {
              this.imageViewWidth = Number(newValue.width);
              this.imageViewHeight = Number(newValue.height);
              this.imageGlobalX = Number(newValue.globalPosition.x);
              this.imageGlobalY = Number(newValue.globalPosition.y);
            })
            .onTouch((event: TouchEvent) => {
              this.handleTouch(event);
            })
            .onMouse((event: MouseEvent) => {
              if (event.action === MouseAction.Move) {
                this.sendMouseMoveAt(event.x, event.y, 0);
                return;
              }
              if (event.button === MouseButton.Right) {
                if (event.action === MouseAction.Press) {
                  this.sendMouseAt(event.x, event.y, true, 2);
                } else if (event.action === MouseAction.Release) {
                  this.sendMouseAt(event.x, event.y, false, 2);
                }
              } else if (event.button === MouseButton.Middle) {
                if (event.action === MouseAction.Press) {
                  this.sendMouseAt(event.x, event.y, true, 3);
                } else if (event.action === MouseAction.Release) {
                  this.sendMouseAt(event.x, event.y, false, 3);
                }
              }
            })
            .onAxisEvent((event: AxisEvent) => {
              const vertical = event.getVerticalAxisValue();
              if (vertical !== 0) {
                sendWheel(vertical > 0 ? -120 : 120);
              }
            })
            .gesture(
              GestureGroup(GestureMode.Parallel,
                TapGesture({ count: 1, fingers: 2 })
                  .onAction((event: GestureEvent) => {
                    if (event.fingerList.length > 0) {
                      const finger = event.fingerList[0];
                      this.sendMouseAt(finger.localX, finger.localY, true, 2);
                      this.sendMouseAt(finger.localX, finger.localY, false, 2);
                    }
                  }),
                PanGesture({ fingers: 2, direction: PanDirection.Vertical, distance: 4 })
                  .onActionStart(() => {
                    this.lastPanOffsetY = 0;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const delta = event.offsetY - this.lastPanOffsetY;
                    if (Math.abs(delta) >= 10) {
                      sendWheel(delta > 0 ? -120 : 120);
                      this.lastPanOffsetY = event.offsetY;
                    }
                  }),
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => {
                    this.pinchStartScale = this.viewScale;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.viewScale = Math.max(0.5, Math.min(3, this.pinchStartScale * event.scale));
                  })
              )
            )
        } else {
          Column() {
            Text(this.connected ? '等待远程画面…' : '连接后在此显示远程桌面')
              .fontSize(14)
              .fontColor('#9CA3AF')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.connected ? '#000000' : '#EEF1F6')
          .borderRadius(8)
        }


        if (this.connected) {
          Row()
            .width('100%')
            .height(64)
        }

        if (!this.connected) {
          Text(`native ${version()} · FreeRDP ${freerdpVersion()}`)
            .fontSize(11)
            .fontColor('#9CA3AF')
            .width('100%')
        }
      }
      .padding(this.connected ? 8 : 20)
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#F7F9FC')

      if (this.connected) {
        Row({ space: 4 }) {
          TextInput({ placeholder: '本地文本输入（点画面切回远程键盘）', text: this.keyboardText })
            .onChange((value: string) => {
              this.keyboardText = value;
            })
            .onFocus(() => {
              this.onInputFocus();
            })
            .onBlur(() => {
              this.onInputBlur();
            })
            .height(56)
            .borderRadius(4)
            .layoutWeight(1)

          Button() {
            Row({ space: 4 }) {
              Text('✈').fontSize(16).fontColor(this.keyFg())
              Text('发送').fontSize(12).fontColor(this.keyFg())
            }
          }
          .width(110)
          .height(56)
          .borderRadius(4)
          .backgroundColor(this.keyBg())
          .stateStyles({
            pressed: {
              .backgroundColor('#2563EB')
            }
          })
          .onClick(() => {
            this.sendKeyboard();
          })

          Button() {
            Row({ space: 4 }) {
              Text('✥').fontSize(16).fontColor(this.moveMode ? '#FFFFFF' : this.keyFg())
              Text('移动').fontSize(12).fontColor(this.moveMode ? '#FFFFFF' : this.keyFg())
            }
          }
          .width(120)
          .height(56)
          .borderRadius(4)
          .backgroundColor(this.moveMode ? '#2563EB' : this.keyBg())
          .stateStyles({
            pressed: {
              .backgroundColor('#2563EB')
            }
          })
          .onClick(() => {
            this.moveMode = !this.moveMode;
          })

          Button() {
            Row({ space: 4 }) {
              Text('⌨').fontSize(16).fontColor(this.keyFg())
              Text(this.keyboardVisible ? '收起' : '键盘').fontSize(12).fontColor(this.keyFg())
            }
          }
          .width(120)
          .height(56)
          .borderRadius(4)
          .backgroundColor(this.keyBg())
          .stateStyles({
            pressed: {
              .backgroundColor('#2563EB')
            }
          })
          .onClick(() => {
            this.toggleVirtualKeyboard();
          })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#F7F9FC')
        .translate({ y: this.keyboardVisible ? -this.virtualKeyboardHeight : (this.systemKeyboardHeight > 0 ? -px2vp(this.systemKeyboardHeight) + 30 : 0) })
      }

      if (this.connected && this.keyboardVisible) {
        Column({ space: 4 }) {
          Row({ space: 4 }) {
            this.Key('Esc', 0x01)
            this.Key2('!', '1', 0x02)
            this.Key2('@', '2', 0x03)
            this.Key2('#', '3', 0x04)
            this.Key2('$', '4', 0x05)
            this.Key2('%', '5', 0x06)
            this.Key2('^', '6', 0x07)
            this.Key2('&', '7', 0x08)
            this.Key2('*', '8', 0x09)
            this.Key2('(', '9', 0x0A)
            this.Key2(')', '0', 0x0B)
            this.Key2('_', '-', 0x0C)
            this.Key2('+', '=', 0x0D)
            this.Key('Backspace', 0x0E, false, 2)
            this.NavKey('Delete', 0x53, true)
          }
          .width('100%')

          Row({ space: 4 }) {
            this.Key('Tab', 0x0F, false, 1)
            this.Key('Q', 0x10)
            this.Key('W', 0x11)
            this.Key('E', 0x12)
            this.Key('R', 0x13)
            this.Key('T', 0x14)
            this.Key('Y', 0x15)
            this.Key('U', 0x16)
            this.Key('I', 0x17)
            this.Key('O', 0x18)
            this.Key('P', 0x19)
            this.Key2('{', '[', 0x1A)
            this.Key2('}', ']', 0x1B)
            this.Key2('|', '\\', 0x2B)
            this.NavKey('PrtSc', 0x37, true)
          }
          .width('100%')

          Row({ space: 4 }) {
            this.Key('Caps', 0x3A, false, 1.5)
            this.Key('A', 0x1E)
            this.Key('S', 0x1F)
            this.Key('D', 0x20)
            this.Key('F', 0x21)
            this.Key('G', 0x22)
            this.Key('H', 0x23)
            this.Key('J', 0x24)
            this.Key('K', 0x25)
            this.Key('L', 0x26)
            this.Key2(':', ';', 0x27)
            this.Key2('\"', "'", 0x28)
            this.Key('Enter', 0x1C, false, 2)
            this.NavKey('PgUp', 0x49, true)
          }
          .width('100%')

          Row({ space: 4 }) {
            this.ModKey('Shift', 0x2A, this.shiftActive || this.shiftLatch, false, 2)
            this.Key('Z', 0x2C)
            this.Key('X', 0x2D)
            this.Key('C', 0x2E)
            this.Key('V', 0x2F)
            this.Key('B', 0x30)
            this.Key('N', 0x31)
            this.Key('M', 0x32)
            this.Key2('<', ',', 0x33)
            this.Key2('>', '.', 0x34)
            this.Key2('?', '/', 0x35)
            this.ModKey('Shift', 0x36, this.shiftActive || this.shiftLatch, false, 2)
            this.NavKey('↑', 0x48, true)
            this.NavKey('PgDn', 0x51, true)
          }
          .width('100%')

          Row({ space: 4 }) {
            Button(this.comboActive ? '组合键•' : '组合键')
              .fontSize(12)
              .height(56)
              .borderRadius(4)
              .layoutWeight(2)
              .backgroundColor(this.comboActive ? '#2563EB' : this.keyBg())
              .fontColor(this.comboActive ? '#FFFFFF' : this.keyFg())
              .stateStyles({
                pressed: {
                  .backgroundColor('#2563EB')
                }
              })
              .onClick(() => {
                this.toggleCombo();
              })
            this.ModKey('Ctrl', 0x1D, this.ctrlActive, false)
            this.NavKey('Win', 0x5B, true)
            this.ModKey('Alt', 0x38, this.altActive, false)
            this.Key('Space', 0x39, false, 5)
            this.ModKey('Alt', 0x38, this.altActive, false)
            this.ModKey('Ctrl', 0x1D, this.ctrlActive, false)
            this.NavKey('←', 0x4B, true)
            this.NavKey('↓', 0x50, true)
            this.NavKey('→', 0x4D, true)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .backgroundColor('#F7F9FC')
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.virtualKeyboardHeight = Number(newValue.height);
        })
      }


    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F9FC')
    .id('remoteKeyboard')
    .focusable(true)
    .defaultFocus(true)
    .onBlur(() => {
      console.info('LanRDP root blur');
      this.releaseModifiers("onBlur");
    })
    .onFocus(() => {
      console.info('LanRDP root focus');
    })
    .onKeyEvent((event: KeyEvent) => {
      this.handleHardwareKey(event);
    })
  }
}
