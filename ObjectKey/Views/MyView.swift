import SwiftData
import SwiftUI
import ObjectKeyCore

/// 마이. 도움말·물건 관리·데이터(백업·삭제)·정보를 한곳에 모은다. 예전에는 기록 화면 ⋯ 메뉴에 흩어져 있었다.
struct MyView: View {
    @Environment(\.modelContext) private var context
    @Environment(ActivityStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var plus = PlusStore.shared
    @State private var showPaywall = false
    @State private var restoreMessage: String?
    @State private var showHelp = false
    @AppStorage(WeeklyRecap.enabledKey) private var weeklyRecap = false
    @State private var showTags = false
    @State private var confirmWipe = false
    @State private var exportDoc: BackupDocument?
    @State private var importing = false
    @State private var backupMessage: String?

    var body: some View {
        List {
            Section {
                Button { showPaywall = true } label: {
                    HStack {
                        Label(plus.isPlus ? "MOKI 플러스 사용 중" : "MOKI 플러스", systemImage: plus.isPlus ? "checkmark.seal.fill" : "sparkles")
                        Spacer()
                        if !plus.isPlus, let price = plus.product?.displayPrice { Text(price).foregroundStyle(.secondary) }
                    }
                }
                if !plus.isPlus {
                    Button("구매 복원", systemImage: "arrow.clockwise") {
                        Task { restoreMessage = await plus.restore() }
                    }
                }
            } footer: {
                Text(plus.isPlus ? "습관 무제한, 위젯·워치, 자세한 통계를 쓸 수 있어요." : "한 번 결제로 평생 써요. 습관 무제한, 위젯·워치, 자세한 통계.")
            }
            Section {
                Button("사용 안내", systemImage: "questionmark.circle") { showHelp = true }
            }
            Section {
                Toggle(isOn: $weeklyRecap) { Label("일요일 저녁 돌아보기 알림", systemImage: "calendar.badge.checkmark") }
                    .onChange(of: weeklyRecap) { _, on in Task { await WeeklyRecap.set(on) } }
            } footer: {
                Text("일요일 저녁 8시에 한 주를 돌아보라고 알려 드려요. 누르면 통계가 열려요.")
            }
            Section("물건") {
                NavigationLink { StickerBookView() } label: { Label("스티커 모음", systemImage: "star.square.on.square") }
                Button("태그 관리", systemImage: "tag") { showTags = true }
                NavigationLink { CalibrationView() } label: { Label("인식 점검", systemImage: "viewfinder") }
            }
            Section {
                Button("알림·건강·카메라 권한", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } header: {
                Text("권한")
            } footer: {
                Text("설정 → MOKI에서 켜고 끌 수 있어요. 꺼도 직접 기록은 그대로 돼요.")
            }
            Section {
                Button("백업 내보내기", systemImage: "square.and.arrow.up") { exportBackup() }
                Button("백업 가져오기", systemImage: "square.and.arrow.down") { importing = true }
                Button("모든 데이터 삭제", systemImage: "trash", role: .destructive) { confirmWipe = true }
            } header: {
                Text("데이터")
            } footer: {
                Text("사진과 기록은 이 휴대폰에만 저장돼요.")
            }
            Section {
                LabeledContent("버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
        }
        .tint(.primary)
        .navigationTitle("마이")
        .sheet(isPresented: $showHelp) { HelpView() }
        .sheet(isPresented: $showPaywall) { PlusPaywall() }
        .alert("구매 복원", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("확인", role: .cancel) {}
        } message: { Text(restoreMessage ?? "") }
        .sheet(isPresented: $showTags) { TagManagerView() }
        .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                      document: exportDoc, contentType: .json,
                      defaultFilename: "MOKI 백업 \(Date.now.formatted(.iso8601.year().month().day()))") { result in
            if case .success = result { backupMessage = "백업을 저장했어요. iCloud Drive에 두면 기기를 바꿔도 가져올 수 있어요." }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            importBackup(from: url)
        }
        .alert("백업", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(backupMessage ?? "")
        }
        .confirmationDialog("등록한 물건, 사진, 기록을 모두 지워요. 되돌릴 수 없어요.", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("모두 삭제", role: .destructive, action: wipe)
        }
    }

    private func exportBackup() {
        do {
            exportDoc = BackupDocument(data: try Backup.encode(try BackupService.makeFile(context: context)))
        } catch {
            backupMessage = "백업 파일을 만들지 못했어요."
        }
    }

    private func importBackup(from url: URL) {
        // 파일 앱에서 고른 파일은 접근 권한을 잠깐 받아야 읽을 수 있다.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try Backup.decode(try Data(contentsOf: url))
            let added = try BackupService.restore(file, context: context)
            backupMessage = added.keys + added.logs + added.notes == 0
                ? "이미 모두 들어 있어요. 새로 가져온 건 없어요."
                : "물건 \(added.keys)개, 기록 \(added.logs)회, 메모 \(added.notes)개를 가져왔어요."
        } catch BackupError.newerVersion(_) {
            backupMessage = "더 새 버전의 MOKI에서 만든 백업이에요. 앱을 업데이트한 뒤 가져와 주세요."
        } catch {
            backupMessage = "백업 파일을 읽지 못했어요. MOKI에서 내보낸 파일인지 확인해 주세요."
        }
    }

    private func wipe() {
        try? context.delete(model: ActivityLog.self)
        try? context.delete(model: DayNote.self)
        try? context.delete(model: ReferenceShot.self)
        try? context.delete(model: KeyObject.self)
        context.saveOrReport()
        store.reset()
    }
}
