/**
 * Material 风格 TOTP 倒计时圆环。
 * remainMs / periodMs → 进度；剩余不足 5 秒时变为强调色提醒即将刷新。
 */
@Component
export struct CountdownRing {
  @Prop remainMs: number = 30000;
  @Prop periodMs: number = 30000;
  @Prop color: string = '#0B57D0';
  @Prop warnColor: string = '#B3261E';
  @Prop trackColor: string = '#E2E4EC';
  @Prop ringSize: number = 32;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Progress({
        value: this.progressPercent(),
        total: 100,
        type: ProgressType.Ring
      })
        .style({
          strokeWidth: 3,
          enableSmoothEffect: false
        })
        .color(this.ringColor())
        .backgroundColor(this.trackColor)
        .width(this.ringSize)
        .height(this.ringSize)
      Text(`${this.secondsLeft()}`)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.ringColor())
        .maxLines(1)
    }
  }

  private progressPercent(): number {
    if (this.periodMs <= 0) {
      return 0;
    }
    const ratio = Math.max(0, Math.min(1, this.remainMs / this.periodMs));
    return Math.round(ratio * 100);
  }

  private secondsLeft(): number {
    return Math.max(0, Math.ceil(this.remainMs / 1000));
  }

  private ringColor(): string {
    return this.remainMs <= 5000 ? this.warnColor : this.color;
  }
}
