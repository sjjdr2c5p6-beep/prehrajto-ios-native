import SwiftUI

struct AccountView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var client = PrehrajToClient.shared

    @State private var loginMode: Int = 0 // 0 = Email & Password, 1 = Refresh Token / Cookie
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var refreshToken: String = ""
    @State private var statusBannerMessage: String?
    @State private var isErrorBanner: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let account = auth.account {
                            activePremiumCard(account)
                        } else {
                            loginFormCard
                        }

                        if let msg = statusBannerMessage {
                            HStack(spacing: 10) {
                                Image(systemName: isErrorBanner ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                    .foregroundStyle(isErrorBanner ? .red : .green)
                                Text(msg)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .glassCard(cornerRadius: 14)
                        }

                        // Benefits Comparison Card
                        premiumBenefitsCard

                        // Server & App Settings
                        settingsCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Premium účet")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Active Premium Card

    private func activePremiumCard(_ account: PremiumAccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.black)
                    Text("PREHRAJ.TO PREMIUM")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppTheme.premiumGradient, in: Capsule())

                Spacer()

                Text("AKTÍVNY")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(account.email)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("Metóda: \(account.authMethod.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stav účtu")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(account.premiumUntil ?? "Aktívne predplatné")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.premiumGold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Výhody")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Originál stream + Offline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            Button(role: .destructive) {
                auth.logout()
                statusBannerMessage = "Účet bol odpojený."
                isErrorBanner = false
            } label: {
                Label("Odhlásiť sa z Premium účtu", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppTheme.premiumGold.opacity(0.55), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Login Card

    private var loginFormCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.premiumGradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: "crown.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.black)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prihlásenie do Prehraj.to")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Údaje sú šifrované v iOS Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Spôsob prihlásenia", selection: $loginMode) {
                Text("E-mail a heslo").tag(0)
                Text("Session / Refresh Token").tag(1)
            }
            .pickerStyle(.segmented)

            if loginMode == 0 {
                VStack(spacing: 12) {
                    TextField("E-mailová adresa (Prehraj.to)", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(13)
                        .background(AppTheme.backgroundPrimary, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    SecureField("Heslo", text: $password)
                        .padding(13)
                        .background(AppTheme.backgroundPrimary, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    Button {
                        Task { await performLogin() }
                    } label: {
                        HStack {
                            if auth.isAuthenticating {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "key.fill")
                                Text("Pripojiť Premium účet")
                                    .fontWeight(.bold)
                            }
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.premiumGradient, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(auth.isAuthenticating)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Označenie účtu (voliteľné, napr. Môj Premium)", text: $email)
                        .textInputAutocapitalization(.never)
                        .padding(13)
                        .background(AppTheme.backgroundPrimary, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    TextField("Hodnota refresh_token alebo PHPSESSID", text: $refreshToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(13)
                        .background(AppTheme.backgroundPrimary, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    Text("Tip: Ak máte na účte zapnuté 2FA alebo Cloudflare ochranu, skopírujte hodnotu cookie `refresh_token` z prehliadača.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await performTokenLogin() }
                    } label: {
                        HStack {
                            Image(systemName: "shield.checkered")
                            Text("Uložiť Premium Token")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.premiumGradient, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 20)
    }

    // MARK: - Benefits Card

    private var premiumBenefitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Čo získate s Premium účtom v aplikácii?")
                .font(.headline)
                .foregroundStyle(.white)

            benefitRow(
                icon: "4k.tv.fill",
                title: "Originálna nekomprimovaná kvalita",
                subtitle: "Prehrávanie priameho originálneho súboru (?do=download) v natívnom AVPlayeri."
            )
            benefitRow(
                icon: "arrow.down.circle.fill",
                title: "Neobmedzené offline sťahovanie",
                subtitle: "Sťahovanie celých filmov a titulkov priamo do úložiska iPhonu/iPadu."
            )
            benefitRow(
                icon: "pip.fill",
                title: "AirPlay 2 a Obraz v obraze (PiP)",
                subtitle: "Plynulé streamovanie do Apple TV / Smart TV a prehrávanie na pozadí."
            )
        }
        .padding(18)
        .glassCard(cornerRadius: 18)
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.premiumGold)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Settings Card

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nastavenia servera")
                .font(.headline)
                .foregroundStyle(.white)

            HStack {
                Label("Doména Prehraj.to", systemImage: "globe")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                Picker("Doména", selection: $client.selectedDomain) {
                    Text("prehraj.to").tag("prehraj.to")
                    Text("prehrajto.cz").tag("prehrajto.cz")
                }
                .pickerStyle(.menu)
                .tint(AppTheme.brandPrimary)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 18)
    }

    // MARK: - Actions

    private func performLogin() async {
        statusBannerMessage = nil
        do {
            try await auth.loginWithCredentials(email: email, password: password)
            password = ""
            isErrorBanner = false
            statusBannerMessage = "Premium účet bol úspešne pripojený!"
        } catch {
            isErrorBanner = true
            statusBannerMessage = error.localizedDescription
        }
    }

    private func performTokenLogin() async {
        statusBannerMessage = nil
        do {
            try await auth.loginWithToken(emailLabel: email, refreshToken: refreshToken)
            refreshToken = ""
            isErrorBanner = false
            statusBannerMessage = "Premium Token bol uložený a aktivovaný!"
        } catch {
            isErrorBanner = true
            statusBannerMessage = error.localizedDescription
        }
    }
}
