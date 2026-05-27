import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct RecordSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var showDatePicker = false
    @State private var showCategoryManager = false
    @FocusState private var noteFieldFocused: Bool
    @StateObject private var speechManager = SpeechManager()

    private var expenseCategories: [Category] {
        categories.filter { $0.type == "expense" }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var incomeCategories: [Category] {
        categories.filter { $0.type == "income" }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var currentCategories: [Category] {
        appState.recordType == .expense ? expenseCategories : incomeCategories
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
                // Handle
                Capsule()
                    .fill(Color.appSeparator)
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)

                // Header
                HStack {
                    Text("记一笔")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.appPrimary)
                    Spacer()
                    // Expense / Income toggle
                    HStack(spacing: 2) {
                        typeButton(label: "支出", type: .expense)
                        typeButton(label: "收入", type: .income)
                    }
                    .padding(2)
                    .background(Color.appSeparator)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                // Amount display
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("¥")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.appSecondary)
                    Text(appState.recordAmount.isEmpty ? "0" : appState.recordAmount)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(.appPrimary)
                        .tracking(-2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Cursor
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.appAccent)
                        .frame(width: 3, height: 48)
                        .opacity(1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                // Category scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(
                        rows: [
                            GridItem(.fixed(38), spacing: 8),
                            GridItem(.fixed(38), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(currentCategories) { cat in
                            CategoryChip(
                                emoji: cat.emoji,
                                name: cat.name,
                                isSelected: appState.recordCategoryName == cat.name
                            )
                            .onTapGesture {
                                appState.recordCategoryName = cat.name
                                appState.recordCategoryEmoji = cat.emoji
                                appState.recordCategoryUserTouched = true
                            }
                        }
                        Button {
                            noteFieldFocused = false
                            showCategoryManager = true
                        } label: {
                            HStack(spacing: 6) {
                                Text("⚙️").font(.system(size: 18))
                                Text("管理").font(.system(size: 13, weight: .medium)).foregroundStyle(.appTertiary)
                            }
                            .frame(height: 38)
                            .padding(.horizontal, 12)
                            .background(Color.appBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .frame(height: 92)
                .padding(.bottom, 6)

                // Date row
                HStack(spacing: 8) {
                    Text("📅").font(.system(size: 16))
                    Text(dateDisplayString)
                        .font(.system(size: 15))
                        .foregroundStyle(.appPrimary)
                    Spacer()
                    Button("修改 ›") { showDatePicker = true }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.appAccent)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.appBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // Note row
                @Bindable var state = appState
                let notePlaceholder: LocalizedStringKey = speechManager.isRecording
                    ? "正在聆听…"
                    : "备注（可选）"
                HStack(spacing: 8) {
                    Text("💬").font(.system(size: 16))
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

                    // Mic button
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
                        Image(systemName: speechManager.isRecording
                              ? "waveform.circle.fill"
                              : "mic.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(speechManager.isRecording
                                             ? Color.appAccent
                                             : Color.appTertiary)
                            .symbolEffect(.pulse, isActive: speechManager.isRecording)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.appBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !speechManager.isRecording else { return }
                    noteFieldFocused = true
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .onChange(of: appState.showRecordSheet) { _, visible in
                    if !visible { speechManager.stop() }
                }

                // Keypad
                KeypadView()

                // Action buttons
                HStack(spacing: 10) {
                    Button(action: { appState.showRecordSheet = false }) {
                        Text("取消")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.appSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.appBg)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        noteFieldFocused = false
                        appState.confirmRecord(context: context, allTransactions: allTransactions)
                    }) {
                        Text("完成")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.appAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.appAccent.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .background(Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: Binding(
                get: { appState.recordDate },
                set: { appState.recordDate = $0 }
            ))
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCategoryManager) {
            CategoryManagementView(initialType: appState.recordType)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            applyPredictedCategory()
        }
        .onChange(of: appState.recordAmount) { _, _ in
            applyPredictedCategory()
        }
    }

    /// 调用 AppState 的智能预测；用户已手动选过分类时不覆盖。
    private func applyPredictedCategory() {
        guard !appState.recordCategoryUserTouched else { return }
        let amount = Double(appState.recordAmount)
        guard let predicted = appState.predictedCategory(
            for: appState.recordDate,
            amount: amount,
            transactions: allTransactions,
            categories: categories,
            type: appState.recordType
        ) else { return }
        appState.recordCategoryName = predicted.name
        appState.recordCategoryEmoji = predicted.emoji
    }

    private var dateDisplayString: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selected = calendar.startOfDay(for: appState.recordDate)
        let diff = calendar.dateComponents([.day], from: selected, to: today).day ?? 0
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let dateStr = f.string(from: appState.recordDate)
        switch diff {
        case 0: return "\(dateStr) · \(String(localized: "今天"))"
        case 1: return "\(dateStr) · \(String(localized: "昨天"))"
        case 2: return "\(dateStr) · \(String(localized: "前天"))"
        default: return dateStr
        }
    }

    @ViewBuilder
    private func typeButton(label: LocalizedStringKey, type: RecordType) -> some View {
        let isSelected = appState.recordType == type

        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? .appAccent : .appSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(isSelected ? Color.appAccentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.appAccent.opacity(0.18) : Color.clear, lineWidth: 1)
            )
            .onTapGesture {
                appState.recordType = type
                // 切换类型 → 用户没手动选过的话，重新预测；选过的话，回退到第一个分类
                appState.recordCategoryUserTouched = false
                applyPredictedCategory()
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
        return (lang == "zh") ? 92 : 128
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji).font(.system(size: 18))
            Text(name.localizedCategoryName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .appAccent : .appSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: chipWidth, alignment: .leading)
        .background(isSelected ? Color.appAccentSoft : Color.appBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.appAccent : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Keypad
struct KeypadView: View {
    @Environment(AppState.self) private var appState

    private let keys: [[String]] = [
        ["1","2","3"],
        ["4","5","6"],
        ["7","8","9"],
        [".","0","⌫"]
    ]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { key in
                        KeyButton(key: key) { handleKey(key) }
                    }
                }
            }
            Divider()
        }
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
            Text(key)
                .font(key == "⌫" ? .system(size: 20) : .system(size: 24, weight: .regular))
                .foregroundStyle(.appPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(pressed ? Color.appSeparator : ([".", "⌫"].contains(key) ? Color.appBg : Color.appCard))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
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
