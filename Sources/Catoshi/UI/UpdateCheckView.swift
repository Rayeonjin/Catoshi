import SwiftUI

struct UpdateCheckView: View {
    let language: AppLanguage
    @State private var checking = false
    @State private var result: UpdateCheckResult?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Button(language.pick("업데이트 확인", "Check for Updates"), action: check)
                    .disabled(checking)
                if checking {
                    ProgressView().controlSize(.small)
                    Text(language.pick("확인 중…", "Checking…"))
                        .font(.system(size: CatoshiType.secondary))
                }
            }
            Text(language.pick("버튼을 누를 때만 GitHub에 접속해 공개된 정식·베타 버전을 확인합니다.", "Connects to GitHub only when you press the button to check public stable and beta releases."))
                .font(.system(size: CatoshiType.secondary))
                .catoshiText(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let result {
                Text(message(for: result))
                    .font(.system(size: CatoshiType.body, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if result.hasUpdate {
                    Text(language.pick("릴리스의 소스를 새 폴더에 풀고 bash setup.sh로 직접 빌드해 주세요.", "Extract the release source into a new folder and build it with bash setup.sh."))
                        .font(.system(size: CatoshiType.secondary))
                        .catoshiText(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Link(language.pick("릴리스 열기", "Open Release"), destination: result.latest.url)
            }
            if let failure {
                Text(failure)
                    .font(.system(size: CatoshiType.body))
                    .catoshiText(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear {
            task?.cancel()
            task = nil
            checking = false
        }
    }

    private func message(for result: UpdateCheckResult) -> String {
        let suffix = result.latest.prerelease ? language.pick(" 베타", " beta") : ""
        if result.hasUpdate {
            return language.pick("새 버전이 있습니다: v\(AppMetadata.version) → \(result.latest.tagName)\(suffix)", "Update available: v\(AppMetadata.version) → \(result.latest.tagName)\(suffix)")
        }
        if result.isAhead {
            return language.pick("현재 v\(AppMetadata.version)은 공개 릴리스 \(result.latest.tagName)보다 새로운 버전입니다.", "Current v\(AppMetadata.version) is newer than public release \(result.latest.tagName).")
        }
        return language.pick("현재 최신 버전입니다: \(result.latest.tagName)\(suffix)", "You’re up to date: \(result.latest.tagName)\(suffix)")
    }

    private func check() {
        guard !checking else { return }
        checking = true
        result = nil
        failure = nil
        task = Task { @MainActor in
            do {
                let checked = try await UpdateCheckService().check(currentVersion: AppMetadata.version)
                guard !Task.isCancelled else { return }
                result = checked
            } catch {
                guard !Task.isCancelled else { return }
                if case UpdateCheckError.rateLimited = error {
                    failure = language.pick("GitHub의 요청 한도에 도달했습니다. 잠시 후 다시 확인하거나 GitHub 링크를 열어 주세요.", "GitHub’s request limit was reached. Try again later or open the GitHub link.")
                } else {
                    failure = language.pick("업데이트를 확인하지 못했습니다. 인터넷 연결을 확인하고 다시 시도하거나 GitHub 링크를 열어 주세요.", "Couldn’t check for updates. Check your connection and retry, or open the GitHub link.")
                }
            }
            checking = false
            task = nil
        }
    }
}
