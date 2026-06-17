import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct RecordSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query private var merchantRules: [MerchantCategoryRule]

    @State private var showDatePicker = false
    @State private var showCategoryPicker = false
    @State private var noteVisible = false
    @State private var predictionDebounceTask: Task<Void, Never>?
    @State private var rankedCategoryNames: [String] = []
    @State private var cursorVisible = true
    @FocusState private var noteFieldFocused: Bool
    @StateObject private var speechManager = SpeechManager()

    // 语音记账：listening = 聆听并实时转写，preview = 展示解析结果待确认。
    // 与备注口述（note 字段那个 mic）分开——这是「说一句记一笔」的主路径。
    enum VoicePhase { case idle, listening, preview }
    @State private var voicePhase: VoicePhase = .idle
    @State private var voiceTranscript = ""
    @State private var voiceParseFailed = false

    private var canConfirm: Bool {
        guard let amount = Double(appState.recordAmount) else { return false }
        return amount > 0
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.type == "expense" }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var incomeCategories: [Category] {
        categories.filter { $0.type == "income" }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var currentCategories: [Category] {
        appState.recordType == .expense ? expenseCategories : incomeCategories
    }

    /// 按预测分数排序后的当前类型分类，列表头是最可能的分类。
    /// rankedCategoryNames 由 .onAppear / .onChange 更新；如果缺失则回退到自然顺序。
    private var rankedCurrentCategories: [Category] {
        guard !rankedCategoryNames.isEmpty else { return currentCategories }
        let byName = Dictionary(uniqueKeysWithValues: currentCategories.map { ($0.name, $0) })
        let ranked = rankedCategoryNames.compactMap { byName[$0] }
        // 普通情况：ranked 覆盖所有候选，跳过 leftover 合并
        guard ranked.count < currentCategories.count else { return ranked }
        let rankedSet = Set(ranked.map(\.name))
        return ranked + currentCategories.filter { !rankedSet.contains($0.name) }
    }

    private var noteIsActive: Bool {
        noteVisible || !appState.recordNote.isEmpty || speechManager.isRecording
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    noteFieldFocused = false
                    appState.showRecordSheet = false
                }

            // Sheet
            VStack(spacing: 0) {
                // Grab handle
                Capsule()
                    .fill(Color.appSeparator)
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)

                // Top bar: cancel + segmented type toggle
                HStack {
                    Button {
                        noteFieldFocused = false
                        appState.showRecordSheet = false
                    } label: {
                        Text("取消")
                            .font(.system(size: 15))
                            .foregroundStyle(.appSecondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 0) {
                        typeButton(label: "支出", type: .expense)
                        typeButton(label: "收入", type: .income)
                    }
                    .padding(3)
                    .background(Color.appBg)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                // Hero amount + meta row
                VStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("¥")
                            .font(.system(size: 28, weight: .regular, design: .rounded))
                            .foregroundStyle(.appSecondary)
                        Text(appState.recordAmount.isEmpty ? "0" : appState.recordAmount)
                            .font(.system(size: 60, weight: .semibold, design: .rounded))
                            .foregroundStyle(.appPrimary)
                            .tracking(-1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText(value: Double(appState.recordAmount) ?? 0))
                        Rectangle()
                            .fill(Color.appAccent)
                            .frame(width: 3, height: 44)
                            .opacity(cursorVisible ? 1 : 0)
                            .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: cursorVisible)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)

                    metaRow
                }
                .padding(.top, 24)
                .padding(.bottom, 22)

                // Expanded note field (only when active)
                @Bindable var state = appState
                let notePlaceholder: LocalizedStringKey = speechManager.isRecording
                    ? "正在聆听…"
                    : "添加备注…"
                if noteIsActive {
                    HStack(spacing: 10) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 14))
                            .foregroundStyle(.appTertiary)
                        TextField(notePlaceholder, text: $state.recordNote)
                            .font(.system(size: 15))
                            .foregroundStyle(.appPrimary)
                            .focused($noteFieldFocused)
                            .disabled(speechManager.isRecording)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("完成记账") {
                                        noteFieldFocused = false
                                        appState.confirmRecord(context: context, allTransactions: allTransactions)
                                    }
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.appAccent)
                                }
                            }
                        Button {
                            noteFieldFocused = false
                            if speechManager.isRecording {
                                speechManager.stop()
                            } else {
                                speechManager.start { recognized in
                                    appState.recordNote = recognized
                                }
                            }
                        } label: {
                            Image(systemName: speechManager.isRecording ? "waveform" : "mic")
                                .font(.system(size: 16))
                                .foregroundStyle(speechManager.isRecording ? Color.appAccent : Color.appTertiary)
                                .symbolEffect(.pulse, isActive: speechManager.isRecording)
                                .frame(width: 32, height: 32)
                                .background(Color.appBg)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !speechManager.isRecording else { return }
                        noteFieldFocused = true
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Category — 预测排序的单行（覆盖高频）+ 末尾常驻「全部」入口（查找交给网格 picker，
                // 避免横滑当搜索用：预测准则一点搞定，预测不准则一点展开、扫视即选）
                HStack(spacing: 8) {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) {
                                ForEach(rankedCurrentCategories) { cat in
                                    CategoryChip(
                                        emoji: cat.emoji,
                                        name: cat.name,
                                        isSelected: appState.recordCategoryName == cat.name
                                    )
                                    .id(cat.name)
                                    .onTapGesture {
                                        appState.recordCategoryName = cat.name
                                        appState.recordCategoryEmoji = cat.emoji
                                        appState.recordCategoryUserTouched = true
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        // 用 contentMargins 而非 padding：scrollTo(.leading) 会把首个 chip
                        // 顶到边缘、吃掉普通 padding，contentMargins 才能让左侧留白稳定保留
                        .contentMargins(.leading, 20, for: .scrollContent)
                        .contentMargins(.trailing, 4, for: .scrollContent)
                        .frame(height: 48)
                        .onChange(of: rankedCategoryNames) { _, _ in
                            if let first = rankedCategoryNames.first {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo(first, anchor: .leading)
                                }
                            }
                        }
                    }

                    // 常驻「全部」——常驻不随滚动跑掉，打开现成的网格 picker，一屏扫视全部分类
                    Button {
                        noteFieldFocused = false
                        showCategoryPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 13, weight: .semibold))
                            Text("全部")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.appAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.appAccentSoft.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                }
                .padding(.bottom, 14)

                // Keypad（右列上「再记」、下 ✓）
                KeypadView(
                    canConfirm: canConfirm,
                    onConfirm: {
                        noteFieldFocused = false
                        appState.confirmRecord(context: context, allTransactions: allTransactions)
                    },
                    onContinue: {
                        noteFieldFocused = false
                        appState.confirmRecord(context: context, allTransactions: allTransactions, continueRecording: true)
                    }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 28)
            }
            .background(
                Color.appCard
                    .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
                    .ignoresSafeArea(edges: .bottom)
            )

            // 语音记账叠层：聆听 / 解析预览
            if voicePhase != .idle {
                voiceOverlay
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.22), value: voicePhase)
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: Binding(
                get: { appState.recordDate },
                set: { appState.recordDate = $0 }
            ))
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(isExpense: appState.recordType == .expense) { name, emoji in
                appState.recordCategoryName = name
                appState.recordCategoryEmoji = emoji
                appState.recordCategoryUserTouched = true   // 锁住排序，避免后续输入金额时跳位
                // 把选中的分类临时插到单行最前——选完它就在眼前，不用再找；
                // onChange(rankedCategoryNames) 会顺势把它滚到最左
                withAnimation(.easeInOut(duration: 0.25)) {
                    var names = rankedCategoryNames.isEmpty ? currentCategories.map(\.name) : rankedCategoryNames
                    names.removeAll { $0 == name }
                    names.insert(name, at: 0)
                    rankedCategoryNames = names
                }
            }
            // 不设 detent——交给 CategoryPickerSheet 自测高度，刚好容纳全部分类、不截断
        }
        .onAppear {
            applyPredictedCategory()
            noteVisible = false
            cursorVisible = false  // toggle to start the blink animation
            // 首页「说一笔」入口：面板一出现就直接进入语音聆听
            if appState.recordSheetAutoVoice {
                appState.recordSheetAutoVoice = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    startVoiceBookkeeping()
                }
            }
        }
        .onChange(of: appState.recordAmount) { _, _ in
            scheduleApplyPredictedCategory()
        }
        .onChange(of: appState.recordType) { _, _ in
            applyPredictedCategory()
        }
        .onChange(of: appState.showRecordSheet) { _, visible in
            if !visible {
                speechManager.stop()
                predictionDebounceTask?.cancel()
                voicePhase = .idle
                voiceTranscript = ""
            }
        }
    }

    /// 防抖：用户在敲数字时不立即重新预测，停顿 400ms 后才更新——避免 chip 在每次按键时跳变。
    private func scheduleApplyPredictedCategory() {
        predictionDebounceTask?.cancel()
        predictionDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            applyPredictedCategory()
        }
    }

    /// 调用 AppState 的智能预测；只有用户未手动选过分类时才刷新排序和默认选中。
    /// 一旦用户手动选过，排序就锁住——避免后续金额输入导致选中的 chip 跳位。
    private func applyPredictedCategory() {
        guard !appState.recordCategoryUserTouched else { return }
        let amount = Double(appState.recordAmount)
        let ranked = appState.predictedCategoriesRanked(
            for: appState.recordDate,
            amount: amount,
            transactions: allTransactions,
            categories: categories,
            type: appState.recordType
        )
        let newNames = ranked.map(\.name)
        let namesChanged = newNames != rankedCategoryNames
        let top = ranked.first
        let topChanged = top != nil && top?.name != appState.recordCategoryName
        guard namesChanged || topChanged else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if namesChanged { rankedCategoryNames = newNames }
            if topChanged, let top {
                appState.recordCategoryName = top.name
                appState.recordCategoryEmoji = top.emoji
            }
        }
    }

    /// 日期 + 备注的并排 pill 行——简约高级感的关键。
    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 8) {
            // Date pill
            Button {
                noteFieldFocused = false
                showDatePicker = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                    Text(dateDisplayString)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.appSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.appBg)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Note pill — only when collapsed
            if !noteIsActive {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        noteVisible = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        noteFieldFocused = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("备注")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.appAccent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Color.appAccentSoft.opacity(0.55))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            // 语音记账 pill——说一句话，自动解析金额/备注
            Button {
                startVoiceBookkeeping()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("语音")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.appAccent)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.appAccentSoft.opacity(0.55))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var dateDisplayString: String {
        let cal = Calendar.current
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: appState.recordDate), to: cal.startOfDay(for: Date())).day ?? 0
        switch diff {
        case 0: return String(localized: "今天")
        case 1: return String(localized: "昨天")
        case 2: return String(localized: "前天")
        default:
            let f = DateFormatter()
            f.setLocalizedDateFormatFromTemplate("MMMd")
            return f.string(from: appState.recordDate)
        }
    }

    // MARK: - 语音记账

    @ViewBuilder
    private var voiceOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { cancelVoice() }

            Group {
                switch voicePhase {
                case .listening: voiceListeningCard
                case .preview:   voicePreviewCard
                case .idle:      EmptyView()
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private var voiceListeningCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.appAccentSoft)
                    .frame(width: 76, height: 76)
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.appAccent)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }

            Text(voiceTranscript.isEmpty ? String(localized: "说出金额和用途，例如「咖啡 18 块」") : voiceTranscript)
                .font(.system(size: voiceTranscript.isEmpty ? 14 : 18, weight: voiceTranscript.isEmpty ? .regular : .semibold))
                .foregroundStyle(voiceTranscript.isEmpty ? .appTertiary : .appPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(minHeight: 52)
                .animation(.none, value: voiceTranscript)

            Button {
                finishVoiceCapture()
            } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Color.appAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.appCard))
    }

    private var voicePreviewCard: some View {
        VStack(spacing: 18) {
            if voiceParseFailed {
                Text("没听清金额")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appSecondary)
            }

            // 解析出的金额——主角
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("¥")
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(.appSecondary)
                Text(appState.recordAmount.isEmpty ? "0" : appState.recordAmount)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundStyle(.appPrimary)
                    .tracking(-1)
            }

            // 分类 + 备注（点分类可改）
            VStack(spacing: 10) {
                Button {
                    showCategoryPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(appState.recordCategoryEmoji)
                        Text(appState.recordCategoryName.localizedCategoryName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.appPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.appTertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.appBg))
                }
                .buttonStyle(.plain)

                if !appState.recordNote.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(appState.recordNote)
                        .font(.system(size: 13))
                        .foregroundStyle(.appSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }

            // 确认 / 重说
            HStack(spacing: 10) {
                Button {
                    cancelVoice()
                    startVoiceBookkeeping()
                } label: {
                    Text("重说")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.appAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(Color.appAccentSoft))
                }
                .buttonStyle(.plain)

                Button {
                    voicePhase = .idle
                    appState.confirmRecord(context: context, allTransactions: allTransactions)
                } label: {
                    Text("确认记账")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(Color.appAccent))
                }
                .buttonStyle(.plain)
                .disabled(!canConfirm)
                .opacity(canConfirm ? 1 : 0.4)
            }

            // 退回手动——值已填好，回键盘微调
            Button {
                voicePhase = .idle
            } label: {
                Text("手动修改")
                    .font(.system(size: 13))
                    .foregroundStyle(.appTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.appCard))
    }

    /// 进入语音记账：清空转写、解锁分类排序（让本次重新推断）、开始聆听。
    private func startVoiceBookkeeping() {
        noteFieldFocused = false
        voiceTranscript = ""
        voiceParseFailed = false
        appState.recordCategoryUserTouched = false
        voicePhase = .listening
        speechManager.start { text in
            voiceTranscript = text
        }
    }

    /// 停止聆听，解析转写 → 填充金额/备注/分类 → 进入预览。
    private func finishVoiceCapture() {
        speechManager.stop()
        let transcript = voiceTranscript.trimmingCharacters(in: .whitespaces)
        if let amount = AmountParser.parse(transcript) {
            appState.recordAmount = formatVoiceAmount(amount)
            appState.recordNote = cleanedVoiceNote(transcript)
            voiceParseFailed = false
        } else {
            // 没解析到金额：把整句塞进备注，仍进预览让用户手动改或重说
            appState.recordNote = transcript
            voiceParseFailed = true
        }
        // 关键词分类推断（自学习规则优先）；命中则锁定排序，避免随后金额防抖预测覆盖
        let typeStr = appState.recordType == .expense ? "expense" : "income"
        if let (name, emoji) = BillImportManager.inferCategory(from: transcript, rules: merchantRules, type: typeStr) {
            appState.recordCategoryName = name
            appState.recordCategoryEmoji = emoji
            appState.recordCategoryUserTouched = true
            pinCategoryToFront(name)
        } else {
            applyPredictedCategory()
        }
        voicePhase = .preview
    }

    /// 把某分类临时插到单行最前——和分类条对齐，预览卡里看到的就是它。
    private func pinCategoryToFront(_ name: String) {
        var names = rankedCategoryNames.isEmpty ? currentCategories.map(\.name) : rankedCategoryNames
        names.removeAll { $0 == name }
        names.insert(name, at: 0)
        rankedCategoryNames = names
    }

    private func cancelVoice() {
        speechManager.stop()
        voicePhase = .idle
        voiceTranscript = ""
    }

    /// Double → 键盘用的字符串：整数不带小数，去掉尾随 0。
    private func formatVoiceAmount(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// 从转写里剥掉尾部的金额表达，留下用途描述当备注。
    /// 剥不干净也无妨——预览卡可见，用户能改。
    private func cleanedVoiceNote(_ text: String) -> String {
        let amountChars = CharacterSet(charactersIn: "0123456789.一二两三四五六七八九十百千万零块元角毛分半￥¥$ 　")
        var s = Substring(text)
        while let last = s.unicodeScalars.last, amountChars.contains(last) {
            s = s.dropLast()
        }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? text : trimmed
    }

    @ViewBuilder
    private func typeButton(label: LocalizedStringKey, type: RecordType) -> some View {
        let isSelected = appState.recordType == type

        Text(label)
            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.appPrimary : .appSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.appCard)
                            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    }
                }
            )
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    appState.recordCategoryUserTouched = false
                    appState.recordType = type
                }
            }
    }
}

// MARK: - Category chip
struct CategoryChip: View {
    let emoji: String
    let name: String
    let isSelected: Bool

    private var chipWidth: CGFloat {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return (lang == "zh") ? 88 : 124
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji).font(.system(size: 17))
            Text(name.localizedCategoryName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .appSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: chipWidth, alignment: .leading)
        .background(
            Capsule()
                .fill(isSelected ? Color.appAccent : Color.appBg)
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
    }
}

// MARK: - Keypad
/// 4 列布局：左 3 列为数字 (1-9 + . + 0)；右 1 列分两段——上半 ⌫，下半 ✓ ——各占 2 行高度。
/// 拇指在键盘内即可完成"按数字 → 确认"，且 ⌫ 和 ✓ 的方正比例避免了长瘦感。
struct KeypadView: View {
    @Environment(AppState.self) private var appState
    let canConfirm: Bool
    let onConfirm: () -> Void
    let onContinue: () -> Void

    private let leftKeys: [[String]] = [
        ["1","2","3"],
        ["4","5","6"],
        ["7","8","9"],
        [".","0","⌫"]  // ⌫ 回到原位
    ]

    private let rowHeight: CGFloat = 56
    private var keypadHeight: CGFloat { rowHeight * 4 }

    var body: some View {
        HStack(spacing: 8) {
            // 左侧 3×4 数字 grid
            VStack(spacing: 0) {
                ForEach(leftKeys, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { key in
                            KeyButton(key: key) { handleKey(key) }
                        }
                    }
                }
            }

            // 右列上下两键：上「再记」（存这笔+继续记），下 ✓（存完即关）
            VStack(spacing: 8) {
                ContinueKey(canConfirm: canConfirm, action: onContinue)
                    .frame(height: (keypadHeight - 8) / 2)
                ConfirmKey(canConfirm: canConfirm, action: onConfirm)
                    .frame(height: (keypadHeight - 8) / 2)
            }
            .frame(width: 78)
        }
        .frame(height: keypadHeight)
    }

    private func handleKey(_ k: String) {
        var amt = appState.recordAmount
        switch k {
        case "⌫":
            if !amt.isEmpty { amt.removeLast() }
        case ".":
            if !amt.contains(".") { amt += "." }
        default:
            if let dot = amt.firstIndex(of: ".") {
                let decimals = amt.distance(from: amt.index(after: dot), to: amt.endIndex)
                if decimals >= 2 { return }
            }
            if amt == "0" { amt = k } else { amt += k }
            if amt.count > 8 { return }
        }
        appState.recordAmount = amt
    }
}

struct KeyButton: View {
    let key: String
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if key == "⌫" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.appPrimary)
                } else {
                    Text(key)
                        .font(.system(size: 26, weight: .regular, design: .rounded))
                        .foregroundStyle(.appPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(pressed ? Color.appBg : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

/// 右列上方的「再记」键——次要操作（存这笔+继续记），浅紫底/紫字，和主 ✓ 分主次。
struct ContinueKey: View {
    let canConfirm: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .semibold))
                Text("再记")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(canConfirm ? Color.appAccent : Color.appAccent.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(canConfirm
                          ? (pressed ? Color.appAccentSoft.opacity(0.75) : Color.appAccentSoft)
                          : Color.appAccentSoft.opacity(0.4))
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canConfirm)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .animation(.easeOut(duration: 0.15), value: pressed)
        .animation(.easeOut(duration: 0.2), value: canConfirm)
    }
}

/// 右侧高高的 ✓ 确认键。canConfirm = false 时变为浅紫禁用态。
struct ConfirmKey: View {
    let canConfirm: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(canConfirm
                              ? (pressed ? Color.appAccent.opacity(0.85) : Color.appAccent)
                              : Color.appAccent.opacity(0.32))
                )
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canConfirm)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .animation(.easeOut(duration: 0.15), value: pressed)
        .animation(.easeOut(duration: 0.2), value: canConfirm)
    }
}

// MARK: - Date picker sheet
struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择日期")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.appAccent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            DatePicker(
                "",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(.appAccent)
            .padding(.horizontal, 12)

            Spacer()
        }
        .background(Color.appCard)
    }
}

// MARK: - Speech recognition manager

final class SpeechManager: ObservableObject {
    @Published var isRecording = false

    private let recognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        ?? SFSpeechRecognizer(locale: .autoupdatingCurrent)
    }()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    /// Request permissions then begin live recognition.
    /// `onUpdate` is called on the main thread with each partial transcript.
    func start(onUpdate: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.beginCapture(onUpdate: onUpdate) }
            }
        }
    }

    private func beginCapture(onUpdate: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else { return }

        // Clean up any previous session
        task?.cancel(); task = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true
        // 隐私优先：支持的机型强制纯设备端转写，音频不离开手机；
        // 旧机型（不支持 on-device）回退到 Apple 服务器转写。
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { onUpdate(text) }
                if result.isFinal { DispatchQueue.main.async { self?.stop() } }
            }
            if error != nil { DispatchQueue.main.async { self?.stop() } }
        }

        let node   = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.request?.append(buf)
        }

        engine.prepare()
        do {
            try engine.start()
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            stop()
        }
    }

    func stop() {
        guard engine.isRunning || task != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel(); task = nil
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
        isRecording = false
    }
}
