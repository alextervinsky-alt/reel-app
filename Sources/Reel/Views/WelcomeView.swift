#if os(macOS)
import SwiftUI
import ReelCore

/// First launch: connect TMDB, then choose the film drive.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var token = ""
    @State private var checking = false
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Reel")
                        .font(.system(size: 34, weight: .bold))
                    Text("Two steps and your films are on screen.")
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                step(1, "Connect to TMDB", done: model.hasToken) {
                    if model.hasToken {
                        Text("Connected.").foregroundStyle(.secondary)
                    } else {
                        Text("Reel gets posters and film info from TMDB. Paste your “API Read Access Token” from themoviedb.org → Settings → API.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            SecureField("API Read Access Token", text: $token)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { connect() }
                            if checking { ProgressView().controlSize(.small) }
                            Button("Connect") { connect() }
                                .disabled(token.isEmpty || checking)
                        }
                        if let problem {
                            Text(problem).font(.callout).foregroundStyle(Color.orange)
                        }
                    }
                }

                step(2, "Choose your film drive", done: !model.drives.isEmpty) {
                    Text("Reel reads only the file names. It never opens, moves or changes your films, and never writes to the drive.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Choose Drive…") { model.chooseDrive() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.hasToken)
                }

                Text("Everything Reel saves stays in Documents › Reel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(48)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Reel")
    }

    private func step<Content: View>(_ number: Int, _ title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Theme.panel)
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Color.white)
                } else {
                    Text("\(number)").font(.callout.bold())
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
    }

    private func connect() {
        guard !token.isEmpty, !checking else { return }
        checking = true
        problem = nil
        let candidate = token
        Task {
            problem = await model.connect(token: candidate)
            checking = false
            if problem == nil { token = "" }
        }
    }
}
#endif
