import { image } from '@kit.ImageKit';
import { connect, freerdpVersion, getFrame, sendMouse, sendUnicode, sendWheel, stopSession, version } from 'liblanrdp.so';

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
  @State private frameImage: image.PixelMap | null = null;
  @State private frameVersion: number = 0;
  @State private frameWidth: number = 0;
  @State private frameHeight: number = 0;
  @State private imageViewWidth: number = 0;
  @State private imageViewHeight: number = 0;
  @State private mouseButton: number = 1;
  @State private keyboardText: string = '';
  private mouseDown: boolean = false;
  private timer: number = -1;

  aboutToDisappear(): void {
    this.stopFrameTimer();
    stopSession();
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
      return;
    }
    const touch = event.touches[0];
    if (event.type === TouchType.Down) {
      this.mouseDown = true;
      this.sendMouseAt(touch.x, touch.y, true);
    } else if (event.type === TouchType.Move && this.mouseDown) {
      this.sendMouseAt(touch.x, touch.y, true);
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.mouseDown = false;
      this.sendMouseAt(touch.x, touch.y, false);
    }
  }

  private sendMouseAt(x: number, y: number, down: boolean): void {
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
    const remoteY = Math.floor((y - top) / scale);
    sendMouse(remoteX, remoteY, this.mouseButton, down);
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

  build() {
    Column({ space: 10 }) {
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

      Row({ space: 8 }) {
        Button('左键')
          .onClick(() => {
            this.mouseButton = 1;
          })
        Button('右键')
          .onClick(() => {
            this.mouseButton = 2;
          })
        Button('中键')
          .onClick(() => {
            this.mouseButton = 3;
          })
        Button('滚轮↑')
          .onClick(() => {
            sendWheel(120);
          })
        Button('滚轮↓')
          .onClick(() => {
            sendWheel(-120);
          })
      }
      .width('100%')

      if (this.frameImage !== null) {
        Image(this.frameImage)
          .width('100%')
          .layoutWeight(1)
          .objectFit(ImageFit.Contain)
          .backgroundColor('#000000')
          .borderRadius(8)
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.imageViewWidth = Number(newValue.width);
            this.imageViewHeight = Number(newValue.height);
          })
          .onTouch((event: TouchEvent) => {
            this.handleTouch(event);
          })
      } else {
        Column() {
          Text('等待远程画面…')
            .fontSize(14)
            .fontColor('#9CA3AF')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#EEF1F6')
        .borderRadius(8)
      }

      Row({ space: 8 }) {
        TextInput({ placeholder: '键盘输入', text: this.keyboardText })
          .onChange((value: string) => {
            this.keyboardText = value;
          })
          .layoutWeight(1)
        Button('发送')
          .onClick(() => {
            this.sendKeyboard();
          })
      }
      .width('100%')

      Text(`native ${version()} · FreeRDP ${freerdpVersion()}`)
        .fontSize(11)
        .fontColor('#9CA3AF')
        .width('100%')
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F7F9FC')
  }
}
