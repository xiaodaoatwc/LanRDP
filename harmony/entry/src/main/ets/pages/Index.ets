import { image } from '@kit.ImageKit';
import { inputMethod } from '@kit.IMEKit';
import { display, KeyboardAvoidMode, promptAction, window } from '@kit.ArkUI';
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
  group?: string;
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
  @State private homeSection: number = 0;
  @State private showEditor: boolean = false;
  @State private showPasswordPrompt: boolean = false;
  @State private groups: string[] = [];
  @State private selectedGroup: string = '';
  @State private editorGroup: string = '';
  @State private showGroupPrompt: boolean = false;
  @State private groupPromptText: string = '';
  @State private groupPromptEditing: boolean = false;
  @State private groupPromptFromEditor: boolean = false;
  @State private promptProfileId: string = '';
  @State private promptPassword: string = '';
  @State private promptRemember: boolean = false;
  @State private editorName: string = '';
  @State private searchText: string = '';
  @State private renamingProfile: boolean = false;
  @State private renameText: string = '';
  private loadingSettings: boolean = false;
  private profilesInitialized: boolean = false;
  private applyingProfile: boolean = false;
  @State private status: string = `FreeRDP ${freerdpVersion()}`;
  @State private isConnecting: boolean = false;
  @State private connected: boolean = false;
  @State private frameImage: image.PixelMap | null = null;
  private frameBack: image.PixelMap | null = null;
  @State private frameVersion: number = 0;
  @State private frameFps: number = 0;
  @State private isFullscreen: boolean = false;
  @State private showRemoteMenu: boolean = false;
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
  @State private viewOffsetX: number = 0;
  @State private viewOffsetY: number = 0;
  @State private viewScale: number = 1;
  @State private systemKeyboardHeight: number = 0;
  @State private virtualKeyboardHeight: number = 0;
  private comboKeys: ComboKey[] = [];
  private heldModifiers: number[] = [];
  private appWindow: window.Window | null = null;
  private panLastX: number = 0;
  private panLastY: number = 0;
  private pinchFocalX: number = 0;
  private pinchFocalY: number = 0;
  private panMoved: boolean = false;
  private pinchStartScale: number = 1;
  private pinchEngaged: boolean = false;
  private pinchAnchorScale: number = 1;
  private pinchAnchorRatio: number = 1;
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
  private fpsFrames: number = 0;
  private fpsStart: number = 0;
  private frameGetTotal: number = 0;
  private framePixelTotal: number = 0;
  private frameStatsCount: number = 0;
  private sessionEpoch: number = 0;
  private longPressTimer: number = -1;
  private longPressTriggered: boolean = false;
  private touchMoved: boolean = false;
  private lastTouchX: number = 0;
  private lastTouchY: number = 0;
  private lastWheelY: number = -1;
  private lastPanOffsetY: number = 0;
  private twoFingerActive: boolean = false;
  private twoFingerTapCandidate: boolean = false;
  private twoFingerScroll: boolean = false;
  private twoFingerStartTime: number = 0;
  private twoFingerStartX: number = 0;
  private twoFingerStartY: number = 0;
  private twoFingerLastX: number = 0;
  private twoFingerLastY: number = 0;
  private twoFingerTapX: number = 0;
  private twoFingerTapY: number = 0;
  private firstFingerX: number = 0;
  private firstFingerY: number = 0;
  private touchTapPending: boolean = false;
  private touchStartX: number = 0;
  private touchStartY: number = 0;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      this.appWindow = win;
      win.on('keyboardHeightChange', (height: number) => {
        console.info(`LanRDP keyboardHeight ${height}`);
        this.systemKeyboardHeight = height;
      });
    });
    this.loadSavedSettings().then(() => {
      if (!this.profilesInitialized && this.savedConnections.length === 0 && this.host.length > 0) {
        this.saveCurrentProfile(false);
      }
    });
  }

  onPageShow(): void {
    this.getUIContext().setKeyboardAvoidMode(this.showEditor ? KeyboardAvoidMode.RESIZE : KeyboardAvoidMode.NONE);
    if (this.connected) {
      setTimeout(() => {
        this.focusRemoteKeyboard();
      }, 50);
    }
  }

  aboutToDisappear(): void {
    this.exitFullscreen();
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

  private setEditorKeyboardMode(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  private setRemoteKeyboardMode(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
  }

  private closeEditor(): void {
    this.showEditor = false;
    this.setRemoteKeyboardMode();
  }

  private focusPromptPassword(): void {
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus('promptPassword');
        inputMethod.getController().showSoftKeyboard().catch(() => {
        });
      } catch (error) {
        console.info(`LanRDP focus prompt failed: ${String(error)}`);
      }
    }, 180);
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

  private scrollThreshold(): number {
    const height = this.frameHeight > 0 ? this.frameHeight : 1080;
    return Math.max(24, Math.min(140, 56 * (1080 / height) * this.viewScale));
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
        this.profilesInitialized = true;
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
      const rawGroups = String(await pref.get('groups', ''));
      const loadedGroups: string[] = [];
      if (rawGroups.length > 0) {
        try {
          const parsedGroups = JSON.parse(rawGroups) as string[];
          if (Array.isArray(parsedGroups)) {
            parsedGroups.forEach((group: string) => {
              if (group.length > 0 && !loadedGroups.includes(group)) {
                loadedGroups.push(group);
              }
            });
          }
        } catch (error) {
          console.info(`LanRDP parse groups failed: ${String(error)}`);
        }
      }
      this.savedConnections.forEach((profile: SavedConnection) => {
        const group = profile.group;
        if (group !== undefined && group.length > 0 && !loadedGroups.includes(group)) {
          loadedGroups.push(group);
        }
      });
      this.groups = loadedGroups;

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

  private baseConnections(): SavedConnection[] {
    if (this.homeSection === 2) {
      return this.savedConnections.filter((profile: SavedConnection) => profile.group === this.selectedGroup);
    }
    if (this.homeSection === 3) {
      return this.savedConnections.filter((profile: SavedConnection) =>
        profile.group === undefined || profile.group.length === 0);
    }
    return this.savedConnections;
  }

  private homeCount(): number {
    return this.baseConnections().length;
  }

  private homeTitle(): string {
    if (this.homeSection === 2) {
      return this.selectedGroup;
    }
    if (this.homeSection === 3) {
      return '未分组';
    }
    return '所有电脑';
  }

  private groupCount(name: string): number {
    return this.savedConnections.filter((profile: SavedConnection) => profile.group === name).length;
  }

  private groupOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '未分组' }];
    this.groups.forEach((group: string) => {
      options.push({ value: group });
    });
    return options;
  }

  private filteredConnections(): SavedConnection[] {
    const base = this.baseConnections();
    const query = this.searchText.trim().toLowerCase();
    if (query.length === 0) {
      return base;
    }
    return base.filter((profile: SavedConnection) => {
      return this.connectionLabel(profile).toLowerCase().includes(query) ||
        profile.host.toLowerCase().includes(query) ||
        profile.username.toLowerCase().includes(query);
    });
  }

  private async persistGroups(): Promise<void> {
    try {
      const pref = await this.getPref();
      if (pref === null) {
        return;
      }
      await pref.put('groups', JSON.stringify(this.groups));
      await pref.flush();
    } catch (error) {
      console.info(`LanRDP persist groups failed: ${String(error)}`);
    }
  }

  private openGroupPrompt(edit: boolean, fromEditor: boolean): void {
    if (edit && this.selectedGroup.length === 0) {
      promptAction.showToast({ message: '请先选择一个分组' });
      return;
    }
    this.groupPromptEditing = edit;
    this.groupPromptText = edit ? this.selectedGroup : '';
    this.groupPromptFromEditor = fromEditor;
    this.showGroupPrompt = true;
    this.setEditorKeyboardMode();
  }

  private closeGroupPrompt(): void {
    this.showGroupPrompt = false;
    this.groupPromptText = '';
    if (this.showEditor) {
      this.setEditorKeyboardMode();
    } else {
      this.setRemoteKeyboardMode();
    }
  }

  private async confirmGroupPrompt(): Promise<void> {
    const name = this.groupPromptText.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '分组名称不能为空' });
      return;
    }
    if (this.groupPromptEditing) {
      const old = this.selectedGroup;
      if (name !== old && this.groups.includes(name)) {
        promptAction.showToast({ message: '已存在同名分组' });
        return;
      }
      this.groups = this.groups.map((group: string) => group === old ? name : group);
      this.savedConnections = this.savedConnections.map((profile: SavedConnection) => {
        if (profile.group !== old) {
          return profile;
        }
        return {
          id: profile.id,
          name: profile.name,
          group: name,
          host: profile.host,
          port: profile.port,
          username: profile.username,
          domain: profile.domain,
          resolutionPreset: profile.resolutionPreset,
          scalePreset: profile.scalePreset,
          savePassword: profile.savePassword
        };
      });
      this.selectedGroup = name;
      await this.persistProfiles();
      await this.persistGroups();
      this.status = '已重命名分组';
    } else {
      if (!this.groups.includes(name)) {
        this.groups = this.groups.concat([name]);
      }
      if (this.groupPromptFromEditor) {
        this.editorGroup = name;
      } else {
        this.homeSection = 2;
        this.selectedGroup = name;
        this.showEditor = false;
      }
      await this.persistGroups();
      this.status = '已创建分组';
    }
    this.closeGroupPrompt();
  }

  private async deleteCurrentGroup(): Promise<void> {
    const name = this.selectedGroup;
    if (name.length === 0) {
      return;
    }
    this.groups = this.groups.filter((group: string) => group !== name);
    this.savedConnections = this.savedConnections.map((profile: SavedConnection) => {
      if (profile.group !== name) {
        return profile;
      }
      return {
        id: profile.id,
        name: profile.name,
        group: '',
        host: profile.host,
        port: profile.port,
        username: profile.username,
        domain: profile.domain,
        resolutionPreset: profile.resolutionPreset,
        scalePreset: profile.scalePreset,
        savePassword: profile.savePassword
      };
    });
    this.selectedGroup = '';
    this.homeSection = 0;
    await this.persistProfiles();
    await this.persistGroups();
    this.status = '已删除分组，电脑已移到未分组';
  }

  private connectionLoginLabel(profile: SavedConnection): string {
    return profile.username.length > 0 ? profile.username : '直接输入';
  }

  private connectionDisplayLabel(profile: SavedConnection): string {
    const resolutions: string[] = [
      '自动', '1024×768', '1280×800', '1440×900', '1600×900', '1920×1080'
    ];
    const scales: string[] = ['100%', '125%', '150%', '175%', '200%'];
    const resolution = profile.resolutionPreset >= 0 && profile.resolutionPreset < resolutions.length
      ? resolutions[profile.resolutionPreset] : resolutions[0];
    const scaleIndex = profile.scalePreset !== undefined ? profile.scalePreset : 0;
    const scale = scaleIndex >= 0 && scaleIndex < scales.length ? scales[scaleIndex] : scales[0];
    return `${resolution} · ${scale}`;
  }

  private startAddConnection(): void {
    this.editorName = '';
    this.selectedConnectionId = '';
    this.selectedConnectionIndex = 0;
    this.host = '';
    this.portText = '3389';
    this.username = '';
    this.password = '';
    this.domain = '';
    this.savePassword = false;
    this.resolutionPreset = 0;
    this.scalePreset = 0;
    this.editorGroup = this.homeSection === 2 ? this.selectedGroup : '';
    this.homeSection = 0;
    this.showEditor = true;
    this.setEditorKeyboardMode();
    this.status = '新连接';
  }

  private async startEditConnection(profile: SavedConnection): Promise<void> {
    await this.applyProfile(profile);
    this.showEditor = true;
    this.setEditorKeyboardMode();
  }

  private async saveEditor(connectAfter: boolean): Promise<void> {
    if (this.host.trim().length === 0) {
      promptAction.showToast({ message: '请先填写主机名或 IP' });
      return;
    }
    if (connectAfter && this.password.length === 0) {
      this.status = '请输入密码';
      promptAction.showToast({ message: '请输入密码' });
      return;
    }
    await this.saveCurrentProfile(false);
    this.closeEditor();
    this.homeSection = 0;
    if (connectAfter) {
      await this.doConnect();
      if (!this.connected) {
        this.showEditor = true;
        this.setEditorKeyboardMode();
      }
    }
  }

  private promptProfile(): SavedConnection | null {
    return this.savedConnections.find((item: SavedConnection) => item.id === this.promptProfileId) ?? null;
  }

  private promptSubtitle(): string {
    const profile = this.promptProfile();
    if (profile === null) {
      return '';
    }
    const user = profile.username.length > 0 ? profile.username : '直接输入';
    return `${user} @ ${profile.host}:${profile.port}`;
  }

  private openPasswordPrompt(profile: SavedConnection): void {
    this.promptProfileId = profile.id;
    this.promptPassword = '';
    this.promptRemember = profile.savePassword;
    this.showEditor = false;
    this.showPasswordPrompt = true;
    this.status = '请输入密码';
    this.setEditorKeyboardMode();
    this.focusPromptPassword();
  }

  private closePasswordPrompt(): void {
    this.showPasswordPrompt = false;
    this.promptPassword = '';
    this.setRemoteKeyboardMode();
  }

  private async confirmPasswordAndConnect(): Promise<void> {
    const profile = this.promptProfile();
    if (profile === null) {
      this.closePasswordPrompt();
      return;
    }
    if (this.promptPassword.length === 0) {
      promptAction.showToast({ message: '请输入密码' });
      return;
    }
    await this.applyProfile(profile);
    this.password = this.promptPassword;
    this.savePassword = this.promptRemember;
    this.closePasswordPrompt();
    await this.saveCurrentProfile(false);
    await this.doConnect();
    if (!this.connected) {
      promptAction.showToast({ message: this.status });
    }
  }

  private async connectConnection(profile: SavedConnection): Promise<void> {
    await this.applyProfile(profile);
    if (this.password.length === 0) {
      this.openPasswordPrompt(profile);
      return;
    }
    this.showEditor = false;
    this.setRemoteKeyboardMode();
    await this.doConnect();
    if (!this.connected) {
      promptAction.showToast({ message: this.status });
    }
  }

  private async deleteConnection(profile: SavedConnection): Promise<void> {
    this.selectedConnectionId = profile.id;
    await this.deleteSelectedProfile();
    if (this.showEditor && this.selectedConnectionId.length === 0) {
      this.showEditor = false;
    }
  }

  private async startRename(): Promise<void> {
    if (this.selectedConnectionId.length === 0) {
      await this.saveCurrentProfile(false);
    }
    if (this.selectedConnectionId.length === 0) {
      promptAction.showToast({ message: '请先填写主机名或 IP' });
      return;
    }
    const profile = this.savedConnections.find((item: SavedConnection) => item.id === this.selectedConnectionId);
    if (!profile) {
      promptAction.showToast({ message: '连接记录不存在，请重新保存' });
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
      this.editorName = profile.name !== undefined ? profile.name : '';
      this.editorGroup = profile.group !== undefined ? profile.group : '';
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
    const groupName = this.editorGroup.trim();
    if (groupName.length > 0 && !this.groups.includes(groupName)) {
      this.groups = this.groups.concat([groupName]);
      await this.persistGroups();
    }
    const profile: SavedConnection = {
      id: id,
      name: this.editorName.trim().length > 0 ? this.editorName.trim() : existingName,
      group: groupName,
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
      promptAction.showToast({ message: '请先选择连接记录' });
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
    this.frameBack?.release();
    this.frameBack = null;
    this.frameVersion = 0;
    this.isConnecting = true;
    this.status = '连接中…';
    const desktop = this.resolutionSize();
    const scale = this.scaleValues();
    console.info(`LanRDP connect start ${host}:${port} size=${desktop.width}x${desktop.height} scale=${scale.desktop} hasPassword=${this.password.length > 0}`);

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
        console.info('LanRDP connect ok');
        this.connected = true;
        this.fpsFrames = 0;
        this.fpsStart = 0;
        this.frameFps = 0;
        this.status = '连接成功，等待画面…';
        setTimeout(() => {
          this.focusRemoteKeyboard();
        }, 50);
        this.timer = setInterval(() => {
          this.refreshFrame();
        }, 16);
        this.saveConnectionSettings();
        this.saveCurrentProfile();
      } else {
        const detail = result.startsWith('failed: ') ? result.substring(8) : result;
        this.status = result.startsWith('failed') ? `连接失败：${detail}` : result;
        console.info(`LanRDP connect failed: ${result}`);
      }
    } catch (error) {
      this.status = `连接失败：${String(error)}`;
      console.info(`LanRDP connect error: ${String(error)}`);
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
      const getStart = Date.now();
      const frame = getFrame();
      const getMs = Date.now() - getStart;
      if (!frame) {
        return;
      }
      if (frame.version === this.frameVersion && this.frameImage !== null) {
        return;
      }
      let pixelMs = 0;
      const needsNewBuffers = this.frameImage === null || this.frameBack === null ||
        frame.width !== this.frameWidth || frame.height !== this.frameHeight;
      if (needsNewBuffers) {
        const options: image.InitializationOptions = {
          size: { width: frame.width, height: frame.height },
          pixelFormat: image.PixelMapFormat.BGRA_8888,
          editable: true,
          alphaType: image.AlphaType.OPAQUE
        };
        const pixelStart = Date.now();
        const front = await image.createPixelMap(frame.data, options);
        const back = await image.createPixelMap(frame.data, options);
        pixelMs = Date.now() - pixelStart;
        if (epoch !== this.sessionEpoch) {
          front.release();
          back.release();
          return;
        }
        const after = getSessionInfo();
        if (after.state !== 2) {
          front.release();
          back.release();
          this.onSessionLost(after.error);
          return;
        }
        this.frameImage?.release();
        this.frameBack?.release();
        this.frameImage = front;
        this.frameBack = back;
      } else {
        const target = this.frameBack;
        const previous = this.frameImage;
        if (target === null) {
          return;
        }
        const pixelStart = Date.now();
        await target.writeAllPixelsFromBuffer(frame.data);
        pixelMs = Date.now() - pixelStart;
        if (epoch !== this.sessionEpoch) {
          return;
        }
        const after = getSessionInfo();
        if (after.state !== 2) {
          this.onSessionLost(after.error);
          return;
        }
        this.frameImage = target;
        this.frameBack = previous;
      }
      this.frameGetTotal += getMs;
      this.framePixelTotal += pixelMs;
      this.frameStatsCount++;
      if (this.frameStatsCount >= 60) {
        console.info(`LanRDP frame avg get=${this.frameGetTotal / 60}ms pixel=${this.framePixelTotal / 60}ms`);
        this.frameGetTotal = 0;
        this.framePixelTotal = 0;
        this.frameStatsCount = 0;
      }
      this.frameVersion = frame.version;
      this.frameWidth = frame.width;
      this.frameHeight = frame.height;
      const now = Date.now();
      if (this.fpsStart === 0) {
        this.fpsStart = now;
      }
      this.fpsFrames++;
      if (now - this.fpsStart >= 1000) {
        this.frameFps = Math.round(this.fpsFrames * 1000 / (now - this.fpsStart));
        this.fpsFrames = 0;
        this.fpsStart = now;
      }
      this.status = `已连接 · ${frame.width}×${frame.height} · ${this.scalePercent()} · ${this.frameFps}fps`;

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
    this.exitFullscreen();
    this.stopFrameTimer();
    this.releaseModifiers('sessionLost');
    this.sessionEpoch++;
    this.frameBusy = false;
    this.frameImage?.release();
    this.frameImage = null;
    this.frameBack?.release();
    this.frameBack = null;
    this.frameVersion = 0;
    this.connected = false;
    this.fpsFrames = 0;
    this.fpsStart = 0;
    this.frameFps = 0;
    this.inputFocused = false;
    this.mouseDown = false;
    this.longPressTriggered = false;
    this.viewScale = 1;
    this.viewOffsetX = 0;
    this.viewOffsetY = 0;
    const detail = error.length > 120 ? error.substring(0, 120) : error;
    this.status = detail.length > 0 ? `连接已断开：${detail}` : '连接已断开';
  }

  private finishTwoFingerGesture(): void {
    if (this.twoFingerActive && this.twoFingerTapCandidate && !this.twoFingerScroll &&
        Date.now() - this.twoFingerStartTime < 250) {
      this.sendMouseAt(this.twoFingerTapX, this.twoFingerTapY, true, 2);
      this.sendMouseAt(this.twoFingerTapX, this.twoFingerTapY, false, 2);
    }
    this.twoFingerActive = false;
    this.twoFingerTapCandidate = false;
    this.twoFingerScroll = false;
  }

  private handleTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      this.finishTwoFingerGesture();
      this.cancelLongPress();
      if (this.touchTapPending) {
        if (event.source === SourceType.TouchScreen && Date.now() - this.touchStartTime > 650) {
          this.sendMouseAt(this.lastTouchX, this.lastTouchY, true, 2);
          this.sendMouseAt(this.lastTouchX, this.lastTouchY, false, 2);
        } else {
          this.sendMouseAt(this.lastTouchX, this.lastTouchY, true);
          this.sendMouseAt(this.lastTouchX, this.lastTouchY, false);
        }
      } else if (this.mouseDown && !this.longPressTriggered) {
        this.sendMouseAt(this.lastTouchX, this.lastTouchY, false);
      }
      this.touchTapPending = false;
      this.mouseDown = false;
      this.longPressTriggered = false;
      this.lastWheelY = -1;
      return;
    }

    const touch = event.touches[0];
    const touchX = touch.windowX - this.imageGlobalX;
    const touchY = touch.windowY - this.imageGlobalY;
    if (this.twoFingerActive && (event.type === TouchType.Up || event.type === TouchType.Cancel)) {
      this.finishTwoFingerGesture();
      return;
    }
    if (this.moveMode) {
      if (event.type === TouchType.Down) {
        this.panLastX = touchX;
        this.panLastY = touchY;
        this.panMoved = false;
      } else if (event.type === TouchType.Move) {
        const deltaX = touchX - this.panLastX;
        const deltaY = touchY - this.panLastY;
        if (Math.abs(deltaX) > 2 || Math.abs(deltaY) > 2) {
          this.panMoved = true;
          this.viewOffsetX += deltaX;
          this.viewOffsetY += deltaY;
          this.clampViewOffsets();
        }
        this.panLastX = touchX;
        this.panLastY = touchY;
      }
      return;
    }
    const previousX = this.lastTouchX;
    const previousY = this.lastTouchY;
    this.lastTouchX = touchX;
    this.lastTouchY = touchY;

    if (event.touches.length === 1 && event.type === TouchType.Down && this.twoFingerActive) {
      this.twoFingerActive = false;
      this.twoFingerTapCandidate = false;
      this.twoFingerScroll = false;
    }

    if (event.touches.length >= 2) {
      this.cancelLongPress();
      if (this.mouseDown) {
        this.sendMouseAt(this.lastTouchX, this.lastTouchY, false, 1);
        this.mouseDown = false;
      }
      this.touchTapPending = false;
      this.touchMoved = true;
      const second = event.touches[1];
      const secondX = second.windowX - this.imageGlobalX;
      const secondY = second.windowY - this.imageGlobalY;
      const averageX = (touchX + secondX) / 2;
      const averageY = (touchY + secondY) / 2;
      if (!this.twoFingerActive) {
        this.twoFingerActive = true;
        this.twoFingerTapCandidate = !this.longPressTriggered;
        this.twoFingerScroll = false;
        this.twoFingerStartTime = Date.now();
        this.twoFingerStartX = averageX;
        this.twoFingerStartY = averageY;
        this.twoFingerTapX = this.firstFingerX;
        this.twoFingerTapY = this.firstFingerY;
        this.sendMouseMoveAt(this.firstFingerX, this.firstFingerY, 0);
      }
      this.twoFingerLastX = averageX;
      this.twoFingerLastY = averageY;
      const dx = averageX - this.twoFingerStartX;
      const dy = averageY - this.twoFingerStartY;
      if (Math.sqrt(dx * dx + dy * dy) > 30) {
        this.twoFingerScroll = true;
      }
      this.lastWheelY = -1;
      return;
    }

    if (this.twoFingerActive) {
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.finishTwoFingerGesture();
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
      this.touchStartX = touchX;
      this.touchStartY = touchY;
      this.firstFingerX = touchX;
      this.firstFingerY = touchY;
      this.touchTapPending = true;
      this.mouseDown = false;
      this.touchMoved = false;
      this.longPressTriggered = false;
      this.touchStartTime = Date.now();

      this.cancelLongPress();
      if (event.source === SourceType.TouchScreen) {
        this.longPressTimer = setTimeout(() => {
          if (this.touchTapPending && !this.touchMoved && !this.longPressTriggered && !this.twoFingerActive) {
            this.touchTapPending = false;
            this.sendMouseAt(this.lastTouchX, this.lastTouchY, true, 2);
            this.sendMouseAt(this.lastTouchX, this.lastTouchY, false, 2);
            this.longPressTriggered = true;
          }
        }, 650);
      }
    } else if (event.type === TouchType.Move && (this.mouseDown || this.touchTapPending)) {
      if (this.touchTapPending) {
        if (Math.abs(touchX - this.touchStartX) <= 4 && Math.abs(touchY - this.touchStartY) <= 4) {
          return;
        }
        this.touchTapPending = false;
        this.mouseDown = true;
        this.touchMoved = true;
        this.cancelLongPress();
        this.sendMouseAt(this.touchStartX, this.touchStartY, true);
      }
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
      if (this.touchTapPending) {
        if (event.source === SourceType.TouchScreen && held > 650) {
          this.sendMouseAt(touchX, touchY, true, 2);
          this.sendMouseAt(touchX, touchY, false, 2);
        } else {
          this.sendMouseAt(touchX, touchY, true);
          this.sendMouseAt(touchX, touchY, false);
        }
      } else if (this.mouseDown && !this.longPressTriggered) {
        this.sendMouseAt(touchX, touchY, false);
      }
      this.touchTapPending = false;
      this.mouseDown = false;
      this.longPressTriggered = false;
      this.lastWheelY = -1;
    }
  }

  private baseDisplayScale(): number {
    if (this.frameWidth <= 0 || this.frameHeight <= 0 ||
        this.imageViewWidth <= 0 || this.imageViewHeight <= 0) {
      return 0;
    }
    return Math.min(this.imageViewWidth / this.frameWidth,
      this.imageViewHeight / this.frameHeight);
  }

  private displayImageWidth(): number {
    return this.frameWidth * this.baseDisplayScale() * this.viewScale;
  }

  private displayImageHeight(): number {
    return this.frameHeight * this.baseDisplayScale() * this.viewScale;
  }

  private clampViewOffsets(): void {
    if (this.frameWidth <= 0 || this.frameHeight <= 0 ||
        this.imageViewWidth <= 0 || this.imageViewHeight <= 0) {
      return;
    }
    const maxX = Math.max(0, (this.displayImageWidth() - this.imageViewWidth) / 2);
    const maxY = Math.max(0, (this.displayImageHeight() - this.imageViewHeight) / 2);
    this.viewOffsetX = Math.max(-maxX, Math.min(maxX, this.viewOffsetX));
    this.viewOffsetY = Math.max(-maxY, Math.min(maxY, this.viewOffsetY));
  }

  private sendMouseAt(x: number, y: number, down: boolean, button?: number): void {
    if (this.frameWidth <= 0 || this.frameHeight <= 0 ||
        this.imageViewWidth <= 0 || this.imageViewHeight <= 0) {
      return;
    }
    const base = this.baseDisplayScale();
    if (base <= 0) {
      return;
    }
    const drawWidth = this.displayImageWidth();
    const drawHeight = this.displayImageHeight();
    const left = (this.imageViewWidth - drawWidth) / 2 + this.viewOffsetX;
    const top = (this.imageViewHeight - drawHeight) / 2 + this.viewOffsetY;
    if (x < left || y < top || x >= left + drawWidth || y >= top + drawHeight) {
      return;
    }
    const remoteX = Math.floor((x - left) / (base * this.viewScale));
    const remoteY = Math.floor((y - top) / (base * this.viewScale));
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

  private enterFullscreen(): void {
    this.isFullscreen = true;
    this.showRemoteMenu = false;
    if (this.appWindow !== null) {
      this.appWindow.setWindowLayoutFullScreen(true).catch(() => {
      });
      this.appWindow.setWindowSystemBarEnable([]).catch(() => {
      });
    }
  }

  private exitFullscreen(): void {
    if (!this.isFullscreen) {
      return;
    }
    this.isFullscreen = false;
    this.showRemoteMenu = false;
    if (this.appWindow !== null) {
      this.appWindow.setWindowLayoutFullScreen(false).catch(() => {
      });
      this.appWindow.setWindowSystemBarEnable(['status', 'navigation']).catch(() => {
      });
    }
  }

  private disconnect(): void {
    this.exitFullscreen();
    this.stopFrameTimer();
    this.releaseModifiers("disconnect");
    this.shiftLatch = false;
    stopSession();
    this.sessionEpoch++;
    this.frameBusy = false;
    this.frameImage?.release();
    this.frameImage = null;
    this.frameBack?.release();
    this.frameBack = null;
    this.frameVersion = 0;
    this.viewScale = 1;
    this.viewOffsetX = 0;
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
  }

  private toggleVirtualKeyboard(): void {
    if (this.keyboardVisible) {
      this.keyboardVisible = false;
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
    const base = this.baseDisplayScale();
    if (base <= 0) {
      return;
    }
    const drawWidth = this.displayImageWidth();
    const drawHeight = this.displayImageHeight();
    const left = (this.imageViewWidth - drawWidth) / 2 + this.viewOffsetX;
    const top = (this.imageViewHeight - drawHeight) / 2 + this.viewOffsetY;
    if (x < left || y < top || x >= left + drawWidth || y >= top + drawHeight) {
      return;
    }
    const remoteX = Math.floor((x - left) / (base * this.viewScale));
    const remoteY = Math.floor((y - top) / (base * this.viewScale));
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
    // The user now pans the remote view explicitly; do not fight that with keyboard offsets.
  }

  @Builder
  SidebarRow(icon: string, label: string, section: number) {
    Row({ space: 10 }) {
      Text(icon)
        .fontSize(15)
      Text(label)
        .fontSize(14)
        .fontColor(this.homeSection === section ? '#0A84FF' : '#1C1C1E')
      Blank()
      if (section === 0) {
        Text(String(this.savedConnections.length))
          .fontSize(11)
          .fontColor('#8E8E93')
      } else if (section === 3) {
        Text(String(this.savedConnections.filter((profile: SavedConnection) =>
          profile.group === undefined || profile.group.length === 0).length))
          .fontSize(11)
          .fontColor('#8E8E93')
      }
    }
    .width('100%')
    .height(38)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.homeSection === section && !this.showEditor ? '#0A84FF14' : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      this.homeSection = section;
      this.closeEditor();
    })
  }

  @Builder
  GroupSidebarRow(name: string) {
    Row({ space: 10 }) {
      Text('📁')
        .fontSize(14)
      Text(name)
        .fontSize(13)
        .fontColor(this.homeSection === 2 && this.selectedGroup === name ? '#0A84FF' : '#1C1C1E')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(String(this.groupCount(name)))
        .fontSize(11)
        .fontColor('#8E8E93')
    }
    .width('100%')
    .height(34)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.homeSection === 2 && this.selectedGroup === name && !this.showEditor ? '#0A84FF14' : Color.Transparent)
    .onClick(() => {
      this.homeSection = 2;
      this.selectedGroup = name;
      this.closeEditor();
    })
  }

  @Builder
  Sidebar() {
    Column() {
      Column({ space: 3 }) {
        Text('LanRDP')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1C1C1E')
        Text('HarmonyOS NEXT · 远程桌面')
          .fontSize(11)
          .fontColor('#8E8E93')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 16, right: 16, top: 22, bottom: 18 })

      Text('电脑')
        .fontSize(11)
        .fontColor('#8E8E93')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 6 })

      this.SidebarRow('🖥', '所有电脑', 0)

      ForEach(this.groups, (group: string) => {
        this.GroupSidebarRow(group)
      }, (group: string) => group)

      this.SidebarRow('🗂', '未分组', 3)

      Blank()

      Divider()
        .color('#D1D1D6')
      this.SidebarRow('⚙', '设置', 1)

      Button('＋ 新建分组')
        .width('100%')
        .height(38)
        .fontSize(13)
        .fontColor('#6B7280')
        .backgroundColor(Color.Transparent)
        .borderRadius(8)
        .margin({ left: 8, right: 8 })
        .onClick(() => {
          this.openGroupPrompt(false, false);
        })

      Button('＋ 添加 PC')
        .width('100%')
        .height(38)
        .fontSize(13)
        .fontColor('#0A84FF')
        .backgroundColor(Color.Transparent)
        .borderRadius(8)
        .margin({ left: 8, right: 8, bottom: 12 })
        .onClick(() => {
          this.startAddConnection();
        })
    }
    .width(230)
    .height('100%')
    .backgroundColor('#F2F2F7')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  FormField(label: string, placeholder: string, value: string, onChange: (value: string) => void, password: boolean = false) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(11)
        .fontColor('#6B7280')
      TextInput({ placeholder: placeholder, text: value })
        .type(password ? InputType.Password : InputType.Normal)
        .height(40)
        .fontSize(13)
        .backgroundColor('#F7F7FA')
        .borderRadius(8)
        .onChange((input: string) => {
          onChange(input);
        })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  ConnectionCard(profile: SavedConnection) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Stack() {
          Text('🖥')
            .fontSize(22)
        }
        .width(46)
        .height(46)
        .borderRadius(12)
        .backgroundColor('#EAF2FF')

        Column({ space: 2 }) {
          Text(this.connectionLabel(profile))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1C1C1E')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${profile.host}:${profile.port}`)
            .fontSize(11)
            .fontColor('#8E8E93')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('编辑')
          .fontSize(10)
          .height(26)
          .fontColor('#0A84FF')
          .backgroundColor('#F2F2F7')
          .onClick(() => {
            this.startEditConnection(profile);
          })
        Button('删除')
          .fontSize(10)
          .height(26)
          .fontColor('#FF3B30')
          .backgroundColor('#F2F2F7')
          .onClick(() => {
            this.deleteConnection(profile);
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(profile.group !== undefined && profile.group.length > 0 ? profile.group : '未分组')
          .fontSize(10)
          .fontColor('#6B7280')
          .backgroundColor('#F2F2F7')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
        Text(this.connectionLoginLabel(profile))
          .fontSize(10)
          .fontColor('#6B7280')
        Blank()
        Text(this.connectionDisplayLabel(profile))
          .fontSize(10)
          .fontColor('#8E8E93')
      }
      .width('100%')

      Row() {
        Button('连接')
          .fontSize(12)
          .height(32)
          .backgroundColor('#0A84FF')
          .fontColor(Color.White)
          .onClick(() => {
            this.connectConnection(profile);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(16)
    .border({
      width: this.selectedConnectionId === profile.id ? 2 : 1,
      color: this.selectedConnectionId === profile.id ? '#0A84FF' : '#00000010'
    })
    .onClick(() => {
      this.selectedConnectionId = profile.id;
    })
  }

  @Builder
  HomePage() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text(this.homeTitle())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
          Text(`${this.homeCount()} 台电脑 · 局域网 / 广域网远程桌面`)
            .fontSize(13)
            .fontColor('#8E8E93')
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        if (this.homeSection === 2) {
          Button('重命名')
            .fontSize(12)
            .height(34)
            .fontColor('#0A84FF')
            .backgroundColor('#EAF2FF')
            .onClick(() => {
              this.openGroupPrompt(true, false);
            })
          Button('删除分组')
            .fontSize(12)
            .height(34)
            .fontColor('#FF3B30')
            .backgroundColor('#FFF0EF')
            .onClick(() => {
              this.deleteCurrentGroup();
            })
        }
        Button('＋ 添加 PC')
          .fontSize(13)
          .height(38)
          .backgroundColor('#0A84FF')
          .fontColor(Color.White)
          .onClick(() => {
            this.startAddConnection();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 22, bottom: 14 })

      Row() {
        TextInput({ placeholder: '搜索电脑', text: this.searchText })
          .height(38)
          .width(300)
          .fontSize(13)
          .backgroundColor(Color.White)
          .borderRadius(10)
          .onChange((value: string) => {
            this.searchText = value;
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 14 })

      if (this.baseConnections().length === 0) {
        Column({ space: 12 }) {
          Text(this.homeSection === 2 ? '📁' : '🖥')
            .fontSize(44)
          Text(this.homeSection === 2 ? '这个分组还没有电脑' : '还没有电脑')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
          Text(this.homeSection === 2 ? '添加电脑时会自动归入这个分组。' : '添加一台 Windows 电脑，开始局域网远程桌面。')
            .fontSize(12)
            .fontColor('#8E8E93')
          Button(this.homeSection === 2 ? '添加到此分组' : '添加第一台 PC')
            .fontSize(13)
            .backgroundColor('#0A84FF')
            .fontColor(Color.White)
            .onClick(() => {
              this.startAddConnection();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.filteredConnections().length === 0) {
        Column({ space: 8 }) {
          Text('没有匹配的电脑')
            .fontSize(16)
          Text('换个名称、IP 或用户名试试。')
            .fontSize(12)
            .fontColor('#8E8E93')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.filteredConnections(), (profile: SavedConnection) => {
            GridItem() {
              this.ConnectionCard(profile)
            }
          }, (profile: SavedConnection) => profile.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(16)
        .rowsGap(16)
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 16 })
      }

      if (this.status.includes('失败') || this.status.includes('failed') || this.status.includes('断开') || this.status.includes('请输入')) {
        Text(this.status)
          .fontSize(12)
          .fontColor('#FF3B30')
          .padding({ left: 24, right: 24, bottom: 12 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F2F7')
  }

  @Builder
  SettingsPage() {
    Column() {
      Text('设置')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1C1C1E')
        .width('100%')
        .padding({ left: 24, right: 24, top: 22, bottom: 4 })
      Text('默认显示与关于信息')
        .fontSize(13)
        .fontColor('#8E8E93')
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 14 })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            Text('默认显示')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
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
                .onSelect((index: number) => {
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
                .onSelect((index: number) => {
                  this.scalePreset = index;
                })
            }
            .width('100%')
            Text('新建连接时使用这些默认值。')
              .fontSize(11)
              .fontColor('#8E8E93')
              .width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .border({ width: 1, color: '#00000010' })

          Column({ space: 8 }) {
            Text('关于')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .width('100%')
            Text('LanRDP HarmonyOS 0.1.0')
              .fontSize(12)
            Text(`FreeRDP ${freerdpVersion()}`)
              .fontSize(12)
            Text('密码保存在系统 Asset Store；主机信息保存在 Preferences。')
              .fontSize(11)
              .fontColor('#8E8E93')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(18)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .border({ width: 1, color: '#00000010' })
        }
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F2F7')
  }

  @Builder
  EditorPage() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text(this.selectedConnectionId.length > 0 ? '编辑 PC' : '添加 PC')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1C1C1E')
          Text('远程桌面连接信息')
            .fontSize(12)
            .fontColor('#8E8E93')
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Button('取消')
          .fontSize(12)
          .onClick(() => {
            this.closeEditor();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 22, bottom: 14 })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            Text('常规')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .width('100%')
            this.FormField('名称', '例如：办公室电脑', this.editorName, (value: string) => {
              this.editorName = value;
            })
            this.FormField('主机名或 IP', '192.0.2.10', this.host, (value: string) => {
              this.host = value;
            })
            Row({ space: 12 }) {
              Column() {
                this.FormField('端口', '3389', this.portText, (value: string) => {
                  this.portText = value;
                })
              }
              .layoutWeight(1)
              Column() {
                this.FormField('用户名', 'Windows 用户名', this.username, (value: string) => {
                  this.username = value;
                })
              }
              .layoutWeight(2)
            }
            .width('100%')
            this.FormField('域（可选）', '例如 DESKTOP-ABC', this.domain, (value: string) => {
              this.domain = value;
            })
            Row({ space: 8 }) {
              Text('分组')
                .fontSize(11)
                .fontColor('#6B7280')
                .width(64)
              Select(this.groupOptions())
                .selected(this.editorGroup.length === 0 ? 0 : this.groups.indexOf(this.editorGroup) + 1)
                .value(this.editorGroup.length > 0 ? this.editorGroup : '未分组')
                .font({ size: 13 })
                .layoutWeight(1)
                .onSelect((index: number) => {
                  this.editorGroup = index === 0 ? '' : this.groups[index - 1];
                })
              Button('新建')
                .fontSize(11)
                .height(34)
                .onClick(() => {
                  this.openGroupPrompt(false, true);
                })
            }
            .width('100%')
            this.FormField('密码', '密码', this.password, (value: string) => {
              this.password = value;
            }, true)
            Row({ space: 8 }) {
              Toggle({ type: ToggleType.Switch, isOn: this.savePassword })
                .onChange((isOn: boolean) => {
                  this.savePassword = isOn;
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
          }
          .width('100%')
          .padding(18)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .border({ width: 1, color: '#00000010' })

          Column({ space: 12 }) {
            Text('显示')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
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
                .onSelect((index: number) => {
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
                .onSelect((index: number) => {
                  this.scalePreset = index;
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .border({ width: 1, color: '#00000010' })

          Text(this.status)
            .fontSize(12)
            .fontColor(this.status.includes('失败') ? '#FF3B30' : '#8E8E93')
            .width('100%')
        }
        .width('100%')
        .constraintSize({ maxWidth: 720 })
        .padding({ left: 24, right: 24, bottom: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')

      Row({ space: 10 }) {
        Button('取消')
          .fontSize(13)
          .onClick(() => {
            this.closeEditor();
          })
        Blank()
        Button('保存')
          .fontSize(13)
          .onClick(() => {
            this.saveEditor(false);
          })
        Button('保存并连接')
          .fontSize(13)
          .backgroundColor('#0A84FF')
          .fontColor(Color.White)
          .onClick(() => {
            this.saveEditor(true);
          })
      }
      .width('100%')
      .constraintSize({ maxWidth: 720 })
      .padding({ left: 24, right: 24, top: 12, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F2F7')
  }

  @Builder
  PasswordPrompt() {
    Column() {
      Column({ space: 14 }) {
        Text('输入密码')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1C1C1E')
          .width('100%')
        Text(this.promptSubtitle())
          .fontSize(12)
          .fontColor('#8E8E93')
          .width('100%')

        TextInput({ placeholder: '密码', text: this.promptPassword })
          .type(InputType.Password)
          .height(42)
          .fontSize(13)
          .backgroundColor('#F7F7FA')
          .borderRadius(8)
          .id('promptPassword')
          .defaultFocus(true)
          .onChange((value: string) => {
            this.promptPassword = value;
          })
          .onSubmit(() => {
            this.confirmPasswordAndConnect();
          })
          .width('100%')

        Row({ space: 8 }) {
          Toggle({ type: ToggleType.Switch, isOn: this.promptRemember })
            .onChange((isOn: boolean) => {
              this.promptRemember = isOn;
            })
          Text('记住密码')
            .fontSize(13)
            .fontColor('#374151')
          Text('可选，不勾选则仅本次使用')
            .fontSize(11)
            .fontColor('#9CA3AF')
            .layoutWeight(1)
        }
        .width('100%')

        Row({ space: 10 }) {
          Button('取消')
            .fontSize(13)
            .onClick(() => {
              this.closePasswordPrompt();
            })
          Blank()
          Button('连接')
            .fontSize(13)
            .backgroundColor('#0A84FF')
            .fontColor(Color.White)
            .onClick(() => {
              this.confirmPasswordAndConnect();
            })
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxWidth: 420 })
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(18)
      .shadow({ radius: 30, color: '#00000033', offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#00000055')
  }

  @Builder
  GroupPrompt() {
    Column() {
      Column({ space: 14 }) {
        Text(this.groupPromptEditing ? '重命名分组' : '新建分组')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1C1C1E')
          .width('100%')
        Text(this.groupPromptFromEditor ? '创建后会自动选中这个分组' : '分组用于在左侧整理电脑')
          .fontSize(12)
          .fontColor('#8E8E93')
          .width('100%')
        TextInput({ placeholder: '分组名称', text: this.groupPromptText })
          .height(42)
          .fontSize(13)
          .backgroundColor('#F7F7FA')
          .borderRadius(8)
          .defaultFocus(true)
          .onChange((value: string) => {
            this.groupPromptText = value;
          })
          .onSubmit(() => {
            this.confirmGroupPrompt();
          })
          .width('100%')
        Row({ space: 10 }) {
          Button('取消')
            .fontSize(13)
            .onClick(() => {
              this.closeGroupPrompt();
            })
          Blank()
          Button(this.groupPromptEditing ? '保存' : '创建')
            .fontSize(13)
            .backgroundColor('#0A84FF')
            .fontColor(Color.White)
            .onClick(() => {
              this.confirmGroupPrompt();
            })
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxWidth: 420 })
      .padding(24)
      .backgroundColor(Color.White)
      .borderRadius(18)
      .shadow({ radius: 30, color: '#00000033', offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#00000055')
  }

  @Builder
  HomeShell() {
    Stack() {
      Row() {
        this.Sidebar()
        Column() {
          if (this.showEditor) {
            this.EditorPage()
          } else if (this.homeSection === 1) {
            this.SettingsPage()
          } else {
            this.HomePage()
          }
        }
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .height('100%')

      if (this.showPasswordPrompt) {
        this.PasswordPrompt()
      }

      if (this.showGroupPrompt) {
        this.GroupPrompt()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F2F7')
  }

  @Builder
  RemoteMenu() {
    Column() {
      Column({ space: 12 }) {
        Text('远程菜单')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1C1C1E')
          .width('100%')
        Text(this.status)
          .fontSize(11)
          .fontColor('#8E8E93')
          .width('100%')

        Row({ space: 8 }) {
          Button('中/英')
            .fontSize(12)
            .layoutWeight(1)
            .onClick(() => {
              this.toggleRemoteIME();
              this.showRemoteMenu = false;
            })
          Button(this.shiftCompat ? 'Shift兼容' : 'Shift原生')
            .fontSize(11)
            .layoutWeight(1)
            .onClick(() => {
              this.toggleShiftMode();
            })
          Button('键帽')
            .fontSize(12)
            .layoutWeight(1)
            .onClick(() => {
              this.keyStyle = (this.keyStyle + 1) % 2;
            })
        }
        .width('100%')

        Row({ space: 8 }) {
          Button('复位')
            .fontSize(12)
            .layoutWeight(1)
            .onClick(() => {
              this.viewScale = 1;
              this.viewOffsetX = 0;
              this.viewOffsetY = 0;
            })
          Button(this.moveMode ? '移动中' : '移动')
            .fontSize(12)
            .layoutWeight(1)
            .backgroundColor(this.moveMode ? '#0A84FF' : '#F2F2F7')
            .fontColor(this.moveMode ? '#FFFFFF' : '#1C1C1E')
            .onClick(() => {
              this.moveMode = !this.moveMode;
            })
          Button('键盘')
            .fontSize(12)
            .layoutWeight(1)
            .onClick(() => {
              this.showRemoteMenu = false;
              this.toggleVirtualKeyboard();
            })
          Button('退出全屏')
            .fontSize(12)
            .layoutWeight(1)
            .onClick(() => {
              this.exitFullscreen();
            })
        }
        .width('100%')

        Row({ space: 8 }) {
          Button('关闭')
            .fontSize(12)
            .layoutWeight(1)
            .onClick(() => {
              this.showRemoteMenu = false;
            })
          Button('断开')
            .fontSize(12)
            .fontColor('#FF3B30')
            .layoutWeight(1)
            .onClick(() => {
              this.showRemoteMenu = false;
              this.disconnect();
            })
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxWidth: 520 })
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(18)
      .shadow({ radius: 30, color: '#00000033', offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#66000000')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 8 }) {


        if (!this.connected) {
          this.HomeShell()
        } else {
          if (!this.isFullscreen) {
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
            Button('复位')
              .fontSize(12)
              .onClick(() => {
                this.viewScale = 1;
                this.viewOffsetX = 0;
                this.viewOffsetY = 0;
              })
            Button('全屏')
              .fontSize(12)
              .onClick(() => {
                this.enterFullscreen();
              })
            Button('断开')
              .fontSize(12)
              .onClick(() => {
                this.disconnect();
              })
            }
            .width('100%')
          }
        }

        if (this.frameImage !== null) {
          Stack({ alignContent: Alignment.Center }) {
            Image(this.frameImage)
              .width(this.displayImageWidth())
              .height(this.displayImageHeight())
              .objectFit(ImageFit.Fill)
              .draggable(false)
              .enableAnalyzer(false)
              .backgroundColor(Color.Transparent)
              .offset({ x: this.viewOffsetX, y: this.viewOffsetY })
          }
          .width('100%')
          .layoutWeight(1)
          .clip(true)
          .backgroundColor('#F2F2F7')
          .borderRadius(this.isFullscreen ? 0 : 8)
          .onAreaChange((_oldValue: Area, newValue: Area) => {
              this.imageViewWidth = Number(newValue.width);
              this.imageViewHeight = Number(newValue.height);
              this.imageGlobalX = Number(newValue.globalPosition.x);
              this.imageGlobalY = Number(newValue.globalPosition.y);
              this.clampViewOffsets();
            })
            .onTouch((event: TouchEvent) => {
              this.handleTouch(event);
            })
            .onMouse((event: MouseEvent) => {
              if (event.action === MouseAction.Move) {
                if (!this.mouseDown) {
                  this.sendMouseMoveAt(event.x, event.y, 0);
                }
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
                PanGesture({ fingers: 2, direction: PanDirection.Vertical, distance: 6 })
                  .onActionStart(() => {
                    this.lastPanOffsetY = 0;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const delta = event.offsetY - this.lastPanOffsetY;
                    const threshold = this.scrollThreshold();
                    if (Math.abs(delta) >= threshold) {
                      const steps = Math.min(3, Math.floor(Math.abs(delta) / threshold));
                      const direction = delta > 0 ? 120 : -120;
                      this.twoFingerScroll = true;
                      for (let i = 0; i < steps; i++) {
                        sendWheel(direction);
                      }
                      this.lastPanOffsetY += (delta > 0 ? steps : -steps) * threshold;
                    }
                  }),
                PinchGesture({ fingers: 2 })
                  .onActionStart((event: GestureEvent) => {
                    this.pinchStartScale = this.viewScale;
                    this.pinchEngaged = false;
                    this.pinchAnchorScale = this.viewScale;
                    this.pinchAnchorRatio = 1;
                    if (event.fingerList.length >= 2) {
                      this.pinchFocalX = (event.fingerList[0].localX + event.fingerList[1].localX) / 2;
                      this.pinchFocalY = (event.fingerList[0].localY + event.fingerList[1].localY) / 2;
                    } else {
                      this.pinchFocalX = this.imageViewWidth / 2;
                      this.pinchFocalY = this.imageViewHeight / 2;
                    }
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const ratio = event.scale;
                    if (!this.pinchEngaged) {
                      if (Math.abs(ratio - 1) < 0.15) {
                        return;
                      }
                      this.pinchEngaged = true;
                      this.pinchAnchorScale = this.viewScale;
                      this.pinchAnchorRatio = ratio;
                      this.twoFingerScroll = true;
                    }
                    const oldScale = this.viewScale;
                    const newScale = Math.max(0.8, Math.min(2,
                      this.pinchAnchorScale * (ratio / this.pinchAnchorRatio)));
                    if (newScale !== oldScale) {
                      const ratio = newScale / oldScale;
                      const centerX = this.imageViewWidth / 2;
                      const centerY = this.imageViewHeight / 2;
                      this.viewOffsetX = this.viewOffsetX * ratio +
                        (this.pinchFocalX - centerX) * (1 - ratio);
                      this.viewOffsetY = this.viewOffsetY * ratio +
                        (this.pinchFocalY - centerY) * (1 - ratio);
                      this.viewScale = newScale;
                      this.clampViewOffsets();
                    }
                  })
                  .onActionEnd(() => {
                    this.pinchEngaged = false;
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
          .backgroundColor('#F2F2F7')
          .borderRadius(8)
        }


        if (this.connected && !this.isFullscreen) {
          Row()
            .width('100%')
            .height(64)
        }

      }
      .padding(this.connected ? (this.isFullscreen ? 0 : 8) : 0)
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#F2F2F7')

      if (this.connected && !this.isFullscreen) {
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

      if (this.connected && this.isFullscreen && !this.showRemoteMenu) {
        Button('⋯')
          .width(48)
          .height(48)
          .fontSize(22)
          .borderRadius(24)
          .backgroundColor('#CC000000')
          .fontColor(Color.White)
          .position({ top: 16, right: 16 })
          .onClick(() => {
            this.showRemoteMenu = true;
          })
      }

      if (this.connected && this.showRemoteMenu) {
        this.RemoteMenu()
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
