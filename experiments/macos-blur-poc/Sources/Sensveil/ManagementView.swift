import SwiftUI

public struct ManagementView: View {
    @ObservedObject private var controller: SensveilController

    public init(controller: SensveilController) { self.controller = controller }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Protected applications").font(.title2.bold())
            ForEach(controller.configuration.applications) { application in
                HStack {
                    Text(application.displayName)
                    Spacer()
                    Button {
                        controller.removeApplication(application)
                    } label: {
                        Image(systemName: "trash")
                    }.help("Remove application")
                }
            }
            TextField("Search applications", text: $controller.searchText)
                .textFieldStyle(.roundedBorder)
            List(controller.applications) { application in
                HStack {
                    if let data = application.iconData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().frame(width: 28, height: 28)
                    }
                    VStack(alignment: .leading) {
                        Text(application.displayName)
                        Text(application.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if application.isRunning { Text("Running").font(.caption).foregroundStyle(.secondary) }
                }
            }
            HStack {
                Button("Add Application…") { Task { await controller.addApplication() } }
                Text(controller.freeLimitMessage).font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage = controller.errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }
}
