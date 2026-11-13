import { image } from '@kit.ImageKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { connect, freerdpVersion, getFrame, sendKey, sendMouse, sendMouseMove, sendUnicode, sendWheel, stopSession, version } from 'liblanrdp.so';

interface ComboKey {
  code: number;
  extended: boolean;
}

@Entry
@Component
struct Index {
  @State private host: string = '';
  @State private portText: string = '3389';
  @State private username: string = '';
  @State private password: string = '';
  @State private domain: string = '';
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
  @State private ctrlActive: boolean = false;
  @State private altActive: boolean = false;
  @State private comboActive: boolean = false;
  @State private inputFocused: boolean = false;
  @State private viewOffsetY: number = 0;
  @State private systemKeyboardHeight: number = 0;
  @State private virtualKeyboardHeight: number = 0;
  private comboKeys: ComboKey[] = [];
  private appWindow: window.Window | null = null;
  private panLastY: number = 0;
  private panMoved: boolean = false;
  private mouseDown: boolean = false;
  private timer: number = -1;
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
  }

  onPageShow(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
  }

  aboutToDisappear(): void {
    if (this.appWindow !== null) {
      this.appWindow.off('keyboardHeightChange');
      this.appWindow = null;
    }
    this.stopFrameTimer();
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
    stopSession();
    this.frameImage = null;
    this.frameVersion = 0;
    this.isConnecting = true;
    this.status = '连接中…';

    try {
      const result = await connect(
        host,
        port,
        this.username.trim(),
        this.password,
        this.domain.trim()
      );
      if (result === 'connected') {
        this.connected = true;
        this.status = '连接成功，等待画面…';
        this.timer = setInterval(() => {
          this.refreshFrame();
        }, 200);
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
    if (this.isConnecting) {
      return;
    }
    const frame = getFrame();
    if (!frame) {
      return;
    }
    if (frame.version === this.frameVersion && this.frameImage !== null) {
      return;
    }

    try {
      const options: image.InitializationOptions = {
        size: { width: frame.width, height: frame.height },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false,
        alphaType: image.AlphaType.OPAQUE
      };
      const pixelMap = await image.createPixelMap(frame.data, options);
      this.frameImage?.release();
      this.frameImage = pixelMap;
      this.frameVersion = frame.version;
      this.frameWidth = frame.width;
      this.frameHeight = frame.height;
      this.status = `已连接 · ${frame.width}×${frame.height}`;
    } catch (error) {
      this.status = `渲染失败：${String(error)}`;
    }
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
    if (this.inputFocused || this.keyboardVisible) {
      if (event.type === TouchType.Down) {
        this.panLastY = touch.y;
        this.panMoved = false;
      } else if (event.type === TouchType.Move) {
        const delta = touch.y - this.panLastY;
        if (Math.abs(delta) > 4) {
          this.panMoved = true;
        }
        this.viewOffsetY = Math.max(-this.imageViewHeight * 0.45, Math.min(0, this.viewOffsetY + delta));
        this.panLastY = touch.y;
      }
      return;
    }
    const previousX = this.lastTouchX;
    const previousY = this.lastTouchY;
    this.lastTouchX = touch.x;
    this.lastTouchY = touch.y;

    if (event.touches.length >= 2) {
      this.cancelLongPress();
      if (this.mouseDown) {
        this.sendMouseAt(this.lastTouchX, this.lastTouchY, false, 1);
        this.mouseDown = false;
      }
      const second = event.touches[1];
      const averageY = (touch.y + second.y) / 2;
      if (this.lastWheelY >= 0 && Math.abs(averageY - this.lastWheelY) >= 12) {
        sendWheel(averageY < this.lastWheelY ? 120 : -120);
        this.lastWheelY = averageY;
      } else if (this.lastWheelY < 0) {
        this.lastWheelY = averageY;
      }
      return;
    }

    if (event.type === TouchType.Down) {
      if (!this.inputFocused && !this.keyboardVisible) {
        this.getUIContext().getFocusController().requestFocus('remoteKeyboard');
      }
      this.lastWheelY = -1;
      this.mouseDown = true;
      this.touchMoved = false;
      this.longPressTriggered = false;
      this.sendMouseAt(touch.x, touch.y, true);

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
      if (Math.abs(touch.x - previousX) > 6 || Math.abs(touch.y - previousY) > 6) {
        this.touchMoved = true;
      }
      if (this.touchMoved) {
        this.cancelLongPress();
      }
      if (!this.longPressTriggered) {
        this.sendMouseMoveAt(touch.x, touch.y, this.mouseButton);
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.cancelLongPress();
      if (!this.longPressTriggered) {
        this.sendMouseAt(touch.x, touch.y, false);
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
    const remoteX = Math.floor((x - left) / scale);
    const remoteY = Math.floor((y - this.viewOffsetY - top) / scale);
    sendMouse(remoteX, remoteY, button ?? this.mouseButton, down);
  }

  private tapKey(code: number, extended: boolean = false): void {
    sendKey(code, true, extended);
    sendKey(code, false, extended);
  }

  private handleHardwareKey(event: KeyEvent): void {
    if (event.type !== KeyType.Down) {
      return;
    }
    switch (event.keyCode) {
      case 2054: this.tapKey(0x1C); return;
      case 2055: this.tapKey(0x0E); return;
      case 2070: this.tapKey(0x01); return;
      case 2049: this.tapKey(0x0F); return;
      case 2012: this.tapKey(0x48, true); return;
      case 2013: this.tapKey(0x50, true); return;
      case 2014: this.tapKey(0x4B, true); return;
      case 2015: this.tapKey(0x4D, true); return;
      default: break;
    }
    const text = event.keyText;
    if (text.length === 1) {
      sendUnicode(text.charCodeAt(0), true);
      sendUnicode(text.charCodeAt(0), false);
    }
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
    const remoteX = Math.floor((x - left) / scale);
    const remoteY = Math.floor((y - this.viewOffsetY - top) / scale);
    sendMouseMove(remoteX, remoteY, button ?? this.mouseButton);
  }

  private disconnect(): void {
    this.stopFrameTimer();
    stopSession();
    this.frameImage?.release();
    this.frameImage = null;
    this.frameVersion = 0;
    this.connected = false;
    this.mouseDown = false;
    this.longPressTriggered = false;
    this.status = '已断开';
  }

  private onInputFocus(): void {
    this.inputFocused = true;
    this.keyboardVisible = false;
    this.adjustViewForInput();
    this.panLastY = this.lastTouchY;
  }

  private onInputBlur(): void {
    this.inputFocused = false;
    this.viewOffsetY = 0;
  }

  private toggleVirtualKeyboard(): void {
    if (this.keyboardVisible) {
      this.keyboardVisible = false;
      this.viewOffsetY = 0;
      return;
    }
    this.getUIContext().getFocusController().clearFocus();
    this.inputFocused = false;
    this.keyboardVisible = true;
    this.adjustViewForInput();
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

  private pressKey(code: number, extended: boolean = false): void {
    if (this.comboActive) {
      sendKey(code, true, extended);
      this.comboKeys.push({ code: code, extended: extended });
      return;
    }
    sendKey(code, true, extended);
    sendKey(code, false, extended);
  }

  private toggleCombo(): void {
    if (!this.comboActive) {
      this.comboActive = true;
      this.comboKeys = [];
      return;
    }
    for (let i = this.comboKeys.length - 1; i >= 0; i--) {
      const key = this.comboKeys[i];
      sendKey(key.code, false, key.extended);
    }
    this.comboKeys = [];
    this.comboActive = false;
    this.shiftActive = false;
    this.ctrlActive = false;
    this.altActive = false;
  }

  @Builder
  Key(label: string, code: number, extended: boolean = false, weight: number = 1) {
    Button(label)
      .fontSize(11)
      .height(56)
      .padding(0)
      .constraintSize({ minWidth: 0 })
      .layoutWeight(weight)
      .onClick(() => {
        this.pressKey(code, extended);
      })
  }

  @Builder
  Key2(top: string, bottom: string, code: number, extended: boolean = false, weight: number = 1) {
    Button() {
      Column({ space: 0 }) {
        Text(top)
          .fontSize(9)
          .fontColor('#E5E7EB')
        Text(bottom)
          .fontSize(12)
          .fontColor('#FFFFFF')
      }
      .justifyContent(FlexAlign.Center)
    }
    .height(56)
    .padding(0)
    .constraintSize({ minWidth: 0 })
    .layoutWeight(weight)
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
      .constraintSize({ minWidth: 0 })
      .layoutWeight(weight)
      .backgroundColor(active ? '#2563EB' : '#E5E7EB')
      .fontColor(active ? '#FFFFFF' : '#111827')
      .onClick(() => {
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
    if (this.lastTouchY <= 0 || this.imageViewHeight <= 0) {
      return;
    }
    const keyboardHeight = this.imageViewHeight * 0.42;
    const visibleHeight = Math.max(80, this.imageViewHeight - keyboardHeight);
    if (this.lastTouchY <= visibleHeight * 0.6) {
      this.viewOffsetY = 0;
      return;
    }
    const targetY = visibleHeight * 0.42;
    const desired = targetY - this.lastTouchY;
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
            Button('断开')
              .fontSize(12)
              .onClick(() => {
                this.disconnect();
              })
          }
          .width('100%')

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
            .onAreaChange((_oldValue: Area, newValue: Area) => {
              this.imageViewWidth = Number(newValue.width);
              this.imageViewHeight = Number(newValue.height);
            })
            .onTouch((event: TouchEvent) => {
              this.handleTouch(event);
            })
            .onMouse((event: MouseEvent) => {
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
        Row({ space: 8 }) {
          TextInput({ placeholder: '文本输入（中文/粘贴后可发送）', text: this.keyboardText })
            .onChange((value: string) => {
              this.keyboardText = value;
            })
            .onFocus(() => {
              this.onInputFocus();
            })
            .onBlur(() => {
              this.onInputBlur();
            })
            .layoutWeight(1)
          Button('发送')
            .onClick(() => {
              this.sendKeyboard();
            })
          Button(this.keyboardVisible ? '收起键盘' : '虚拟键盘')
            .onClick(() => {
              this.toggleVirtualKeyboard();
            })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#F7F9FC')
        .translate({ y: this.keyboardVisible ? -this.virtualKeyboardHeight : (this.systemKeyboardHeight > 0 ? -px2vp(this.systemKeyboardHeight) + 20 : 0) })
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
            this.Key('Delete', 0x53, true)
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
            this.Key('PrtSc', 0x37, true)
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
            this.Key('PgUp', 0x49, true)
          }
          .width('100%')

          Row({ space: 4 }) {
            this.ModKey('Shift', 0x2A, this.shiftActive, false, 2)
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
            this.ModKey('Shift', 0x36, this.shiftActive, false, 2)
            this.Key('↑', 0x48, true)
            this.Key('PgDn', 0x51, true, 1)
          }
          .width('100%')

          Row({ space: 4 }) {
            Button(this.comboActive ? '组合键•' : '组合键')
              .fontSize(12)
              .height(56)
              .layoutWeight(2)
              .backgroundColor(this.comboActive ? '#2563EB' : '#E5E7EB')
              .fontColor(this.comboActive ? '#FFFFFF' : '#111827')
              .onClick(() => {
                this.toggleCombo();
              })
            this.ModKey('Ctrl', 0x1D, this.ctrlActive, false)
            this.Key('Win', 0x5B, true)
            this.ModKey('Alt', 0x38, this.altActive, false)
            this.Key('Space', 0x39, false, 5)
            this.ModKey('Alt', 0x38, this.altActive, false)
            this.ModKey('Ctrl', 0x1D, this.ctrlActive, false)
            this.Key('←', 0x4B, true)
            this.Key('↓', 0x50, true)
            this.Key('→', 0x4D, true)
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
    .onKeyEvent((event: KeyEvent) => {
      this.handleHardwareKey(event);
    })
  }
}
