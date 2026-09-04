/**
 * Material 3 分段按钮（Segmented Button）：用于类型/位数/算法等小范围单选。
 * options：显示文本数组；selected：当前选中索引；onSelect：选中回调。
 */
@Component
export struct SegmentedButtons {
  @Prop options: string[] = [];
  @Prop selected: number = 0;
  onSelect: (index: number) => void = () => {};
  @StorageProp('isDark') private isDark: boolean = false;

  build() {
    Row({ space: 0 }) {
      ForEach(this.options, (opt: string, index: number) => {
        Text(opt)
          .fontSize(14)
          .fontWeight(this.selected === index ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selected === index ? '#FFFFFF' : (this.isDark ? '#C4C6D0' : '#44474E'))
          .textAlign(TextAlign.Center)
          .height(38)
          .layoutWeight(1)
          .backgroundColor(this.selected === index ? (this.isDark ? '#A8C7FA' : '#0B57D0') : 'transparent')
          .foregroundColor(this.selected === index ? (this.isDark ? '#062E6F' : '#FFFFFF') : (this.isDark ? '#C4C6D0' : '#44474E'))
          .borderRadius(20)
          .margin({ left: index === 0 ? 0 : 3, right: index === this.options.length - 1 ? 0 : 3 })
          .onClick(() => {
            if (this.selected !== index) {
              this.onSelect(index);
            }
          })
      }, (opt: string) => opt)
    }
    .width('100%')
    .height(44)
    .padding(3)
    .borderRadius(22)
    .backgroundColor(this.isDark ? '#282A2F' : '#E8EAF2')
  }
}
