import { connect, freerdpVersion, version } from 'liblanrdp.so';

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
      this.status = result === 'connected' ? '连接成功（认证通过）' : '连接失败';
    } catch (error) {
      this.status = `连接失败：${String(error)}`;
    } finally {
      this.isConnecting = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('LanRDP')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .width('100%')

      Text('HarmonyOS NEXT · 连接测试')
        .fontSize(14)
        .fontColor('#6B7280')
        .width('100%')
        .margin({ bottom: 8 })

      TextInput({ placeholder: '主机名或 IP，例如 192.0.2.10', text: this.host })
        .onChange((value: string) => {
          this.host = value;
        })
        .width('100%')

      TextInput({ placeholder: '端口', text: this.portText })
        .type(InputType.Number)
        .onChange((value: string) => {
          this.portText = value;
        })
        .width('100%')

      TextInput({ placeholder: '用户名', text: this.username })
        .onChange((value: string) => {
          this.username = value;
        })
        .width('100%')

      TextInput({ placeholder: '密码', text: this.password })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.password = value;
        })
        .width('100%')

      TextInput({ placeholder: '域（可选）', text: this.domain })
        .onChange((value: string) => {
          this.domain = value;
        })
        .width('100%')

      Button(this.isConnecting ? '连接中…' : '测试连接')
        .width('100%')
        .enabled(!this.isConnecting)
        .onClick(() => {
          this.doConnect();
        })

      Text(this.status)
        .fontSize(14)
        .fontColor(this.status.includes('成功') ? '#15803D' : '#6B7280')
        .width('100%')
        .margin({ top: 8 })

      Text(`native ${version()} · FreeRDP ${freerdpVersion()}`)
        .fontSize(12)
        .fontColor('#9CA3AF')
        .width('100%')
        .margin({ top: 16 })
    }
    .padding(24)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F7F9FC')
  }
}
