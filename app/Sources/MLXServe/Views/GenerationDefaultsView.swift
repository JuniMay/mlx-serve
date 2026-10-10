import SwiftUI

struct GenerationDefaultsRows: View {
    @Binding var profile: GenerationDefaults
    var inheritance = "Inherit"
    var fields = GenerationField.allCases
    var allowsForce = true
    var inherited = GenerationDefaults()
    @Environment(\.settingsSearchQuery) private var query

    var body: some View {
        let search = GenerationDefaultsSearch(query: query, fields: fields, inheritance: inheritance)
        if search.hasContent {
            VStack(alignment: .leading, spacing: 0) {
                if search.showsBulkControls {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("All parameters").font(.app(.body))
                            Text(allowsForce
                                 ? "Choose a default value or override values sent by clients."
                                 : "Choose inherited or custom values for this agent.")
                                .font(.app(.caption2)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        GenerationModePicker(value: profile.mode(fields: fields), allowsForce: allowsForce,
                                             inheritance: inheritance, title: "All parameters") {
                            profile.setMode($0, fields: fields, inherited: inherited)
                        }
                        .frame(width: AppLayout.settingsControlWidth, alignment: .leading)
                    }
                    .padding(.vertical, 12)
                    Divider()
                }
                ForEach(search.fields) { field in
                    SearchableRow(searchText: GenerationDefaultsSearch.text(for: field, inheritance: inheritance)) {
                        GenerationParameterRow(field: field, mode: profile.mode(field),
                            value: value(field), hasInheritedValue: inherited.rules[field.rawValue] != nil,
                            inheritance: inheritance, allowsForce: allowsForce,
                            setMode: { profile.setMode($0, field: field, inherited: inherited.rules[field.rawValue]?.value) },
                            setValue: { set($0, field) })
                    }
                    if field != search.fields.last { Divider() }
                }
            }
        }
    }

    private func value(_ field: GenerationField) -> GenerationDefaults.Value {
        profile.rules[field.rawValue]?.value ?? inherited.rules[field.rawValue]?.value ?? field.defaultValue
    }

    private func set(_ value: GenerationDefaults.Value, _ field: GenerationField) {
        let lock = profile.rules[field.rawValue]?.ignoreClient ?? false
        profile.rules[field.rawValue] = .init(value: value, ignoreClient: lock)
    }
}

struct GenerationParameterRow: View {
    let field: GenerationField
    let mode: GenerationDefaults.Mode
    let value: GenerationDefaults.Value
    let hasInheritedValue: Bool
    let inheritance: String
    let allowsForce: Bool
    let setMode: (GenerationDefaults.Mode) -> Void
    let setValue: (GenerationDefaults.Value) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                (Text(L10n.text(field.title)).font(.app(.body))
                 + Text(" · ").font(.app(.caption)).foregroundColor(.secondary)
                 + Text(verbatim: field.parameterName).font(.app(.caption).monospaced()).foregroundColor(.secondary))
                Text(verbatim: field.help)
                    .font(.app(.caption2)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    GenerationModePicker(value: mode, allowsForce: allowsForce,
                        inheritance: inheritance, title: field.title, onChange: setMode)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if mode == .inherited && !hasInheritedValue {
                            Text("—").foregroundStyle(.secondary)
                                .help(L10n.text(inheritance))
                        } else {
                            valueControl.disabled(mode == .inherited)
                        }
                    }
                    .frame(width: 76, alignment: .trailing)
                }
                if field.showsSlider {
                    slider.labelsHidden().accessibilityLabel(L10n.text(field.title))
                        .disabled(mode == .inherited)
                    if let guidance = field.guidance {
                        HStack {
                            Text(L10n.text(guidance.low))
                            Spacer()
                            Text(L10n.text(guidance.high))
                        }
                        .font(.app(.caption2)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: AppLayout.settingsControlWidth)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var slider: some View {
        let binding = Binding(get: { field.sliderPosition(number) },
                              set: { setValue(.number(field.sliderNumber($0))) })
        if let presets = field.presets {
            Slider(value: binding, in: 0...Double(presets.count - 1), step: 1)
        } else {
            Slider(value: binding, in: field.sliderRange)
        }
    }

    private var number: Double {
        if case .number(let n) = value { return n }
        return 0
    }

    @ViewBuilder
    private var valueControl: some View {
        switch field {
        case .thinking:
            Picker("", selection: Binding(
                get: { if case .boolean(let v) = value { return v }; return true },
                set: { setValue(.boolean($0)) })) {
                Text("On").font(.app(.body)).tag(true)
                Text("Off").font(.app(.body)).tag(false)
            }
            .labelsHidden().fixedSize()
        case .effort:
            Picker("", selection: Binding(
                get: { if case .text(let v) = value { return v }; return "low" },
                set: { setValue(.text($0)) })) {
                ForEach(["none", "minimal", "low", "medium", "high", "xhigh", "max"], id: \.self) { word in
                    Text(verbatim: word).font(.app(.body)).tag(word)
                }
            }
            .labelsHidden().fixedSize()
        default:
            TextField("", value: Binding(get: { number },
                set: { if let value = field.numberValue($0) { setValue(value) } }),
                format: .number.grouping(.never).precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                // Fixed: a width that follows the value reflows the row while the slider drags.
                .frame(width: 76)
                .font(.app(.body).monospacedDigit())
                .accessibilityLabel(L10n.text(field.title))
        }
    }
}

struct GenerationModePicker: View {
    let value: GenerationDefaults.Mode?
    let allowsForce: Bool
    let inheritance: String
    let title: String
    let onChange: (GenerationDefaults.Mode) -> Void

    var body: some View {
        Picker(L10n.format("%@ value source", L10n.text(title)), selection: Binding(
            get: { value },
            set: { if let mode = $0 { onChange(mode) } })) {
            if value == nil {
                Text("Mixed").tag(nil as GenerationDefaults.Mode?).disabled(true)
            }
            Text(L10n.text(inheritance)).tag(GenerationDefaults.Mode?.some(.inherited))
            Text("Custom value").tag(GenerationDefaults.Mode?.some(.enabled))
            if allowsForce {
                Text("Override client value").tag(GenerationDefaults.Mode?.some(.forced))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .help(allowsForce
              ? "Inherit the default, use a custom value when a client omits it, or override the client's value."
              : "Inherit the server default or use a custom value for this agent.")
    }
}

struct GlobalGenerationDefaultsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.settingsSearchQuery) private var query
    @State private var profile = GenerationDefaults()
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        let search = GenerationDefaultsSearch(query: query, inheritance: "Model default")
        Group {
            if search.hasContent {
                VStack(alignment: .leading, spacing: 8) {
                    GenerationDefaultsRows(profile: $profile, inheritance: "Model default")
                        .disabled(!loaded)
                    if let error {
                        Text(verbatim: error).font(.app(.caption)).foregroundStyle(.red)
                        Button("Reload settings") { load() }.font(.app(.body))
                    }
                }
            }
        }
        .onAppear {
            if !loaded && error == nil { load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: GenerationDefaultsFile.changed)) { _ in
            guard let saved = try? GenerationDefaultsFile.load(), saved != profile else { return }
            profile = saved
        }
        .onChange(of: profile) { _, value in
            guard loaded else { return }
            do { try GenerationDefaultsFile.save(value); error = nil }
            catch { self.error = "Could not save generation defaults: \(error.localizedDescription)" }
        }
        .disabled(!loaded && error == nil)
    }

    private func load() {
        loaded = false
        do {
            try GenerationDefaultsFile.migrate(appState.serverOptions)
            profile = try GenerationDefaultsFile.load()
            error = nil
            loaded = true
        } catch { self.error = "Could not read generation defaults: \(error.localizedDescription)" }
    }
}
