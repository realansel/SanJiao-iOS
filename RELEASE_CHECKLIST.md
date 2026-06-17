# 青羽记账（Quillion）App Store 上架清单

> 勾掉 `[x]` 表示完成。标注【我】= 代码/素材侧可由 Claude 协助；【你】= 需你本人操作（账号、备案、App Store Connect）。

## 关键信息速查
- App 名称：青羽记账（Quillion）
- Bundle ID：`app.qingyu.ios`
- 内购 ID：`app.qingyu.ios.unlock`（一次买断）
- Xcode 工程 / Scheme：`Qingyu_Quillion.xcodeproj` / scheme `SanJiao`
- 隐私政策 URL：https://realansel.github.io/qingyu-site/privacy.html
- 支持 URL：https://realansel.github.io/qingyu-site/support.html
- 联系邮箱：qingyu_bookkeeping@163.com
- 站点仓库：github.com/realansel/qingyu-site（本地 `~/Documents/Claude/qingyu-site`）

---

## A. 账号与资质【你】
- [ ] Apple Developer Program 会员（¥688/年）已注册且有效
- [ ] 商标「青羽」9类/42类（不阻塞上架，建议尽早提交）

### 备案策略：先裸提交，备案当兜底
青羽不提供「互联网信息服务」（本地存储、无自有服务器；仅用 Apple 系统服务：内购/语音/iCloud），
可先不备案直接提交，被拒再申诉，零成本且可能省下 2–4 周。
- [ ] 第一轮：不填备案号直接提交中国区
- [ ] 若被要求备案 → 提交申诉说明（话术见下，强调"不提供互联网信息服务、仅本地处理"）
- [ ] 兜底（申诉失败才做）：域名 → ICP 主体备案（7–20 工作日）→ App 备案 → 软著
- [ ] 申诉话术：本应用不提供互联网信息服务，数据仅在设备本地处理，仅使用 Apple 系统服务（IAP / 设备端或 Apple 语音识别 / iCloud 备份）

## B. App Store Connect 配置【你】
- [ ] 创建 App 记录（绑定 `app.qingyu.ios`）
- [ ] 创建内购 `app.qingyu.ios.unlock`：定价 + 描述 + 审核截图
- [ ] 元数据（简/繁/英）：名称、副标题、关键词、描述、新功能
- [ ] 上传截图（见 D 项，建议 6.9" 真机重拍）
- [ ] App 隐私标签：勾选「不收集数据」
- [ ] 隐私政策 URL、支持 URL（已就绪，见速查）
- [ ] 类别（财务 / 效率）、年龄分级、版权信息
- [ ] 填入 ICP / App 备案号（中国大陆区必填）

## C. 代码 / 工程收尾
- [x] 出口加密合规 `ITSAppUsesNonExemptEncryption = false`【我·已完成】
- [x] DEBUG 调试面板已 `#if DEBUG` 隔离，不进 Release【已确认】
- [x] 截图假数据种子已移除（备查存于 Design/AppStore截图/demo_seed.swift.txt）【已完成】
- [x] 隐私/权限文案三语一致（简/繁/英）【已核对】
- [x] `appStoreID` 已填入真实 ID `6779131633`（MineView.swift）【我·已完成】
- [x] 应用锁（Face ID / 密码进入 + 设置开关）已实现，描述里「支持应用锁」宣称成立【我·已完成】
- [ ] 版本号确认（当前 1.0 / build 1）

## D. 宣传素材
- [x] App 图标 1024（含深底羽笔 + ¥）【已就绪】
- [x] 7 张宣传图已合成（Design/AppStore截图/output/）【我·已完成】
- [ ] 用真 6.9"（16/17 Pro Max）机型重拍源图并重合成，确保上架尺寸最规范【建议】
- [ ] （可选）英文 / 繁体套图

## E. 真机测试【你 + 我协助】
- [ ] 语音记账：说一句 → 解析金额/分类/备注（模拟器测不了，需真机）
- [ ] 内购 sandbox：购买 / 恢复购买 / 试用到期解锁
- [ ] 账单导入：微信 xlsx / 支付宝 csv 真机走通
- [ ] 试用期 7 天逻辑、深色模式、各机型适配
- [ ] 无崩溃、无占位内容

## F. 提交审核【你】
- [ ] Xcode Archive → 上传（distribution 证书 + profile）
- [ ] TestFlight 自测（可选，建议）
- [ ] 提交审核
- [ ] 常见被拒点自查：内购可用、隐私/支持 URL 有效、元数据准确、中国区备案号已填

---

## 进度判断
技术与素材已走约八成。**真正卡时间的是 A 项的「域名 → ICP/App 备案」（2–4 周）**，建议与开发并行，今天启动。
