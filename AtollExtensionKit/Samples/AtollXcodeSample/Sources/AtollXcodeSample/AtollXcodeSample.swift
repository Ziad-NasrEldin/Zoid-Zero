import AtollExtensionKit

@main
struct AtollXcodeSample {
    static func main() {
        print("AtollExtensionKit version: \(AtollExtensionKitVersion)")
        let descriptor = AtollLiveActivityDescriptor(
            id: "sample-activity",
            title: "Sample Activity",
            subtitle: "Demo",
            leadingIcon: .symbol(name: "star.fill", size: 16)
        )
        print("Descriptor valid: \(descriptor.isValid)")
        _ = AtollClient.shared
        print("AtollClient shared instance ready")
    }
}
