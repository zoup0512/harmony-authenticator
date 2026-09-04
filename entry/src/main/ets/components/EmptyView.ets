import { Theme } from '../common/Theme';

/** 空状态视图 */
@Component
export struct EmptyView {
  @StorageProp(Theme.KEY_DARK_MODE) private isDark: boolean = false;
  @Prop title: string = '暂无账户';
  @Prop subtitle: string = '点击右下角按钮添加第一个验证账户';

  build() {
    Column({ space: 12 }) {
      Text('🔐')
        .fontSize(56)
        .margin({ bottom: 4 })
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.palette(this.isDark).onSurface)
      Text(this.subtitle)
        .fontSize(14)
        .fontColor(Theme.palette(this.isDark).onSurfaceVariant)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 96, left: 40, right: 40 })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }
}
