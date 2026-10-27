import Foundation
import SwiftUI
import WatchKit

@MainActor
final class WatchGateViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case opening
        case success
        case failure(String)
    }

    @Published private(set) var state: State = .idle

    func openDoor() async {
        guard let client = GateStore.makeClient() else {
            state = .failure("Not paired. Open the iPhone app first.")
            WKInterfaceDevice.current().play(.failure)
            return
        }
        state = .opening
        WKInterfaceDevice.current().play(.click)
        do {
            try await client.openDoor()
            state = .success
            WKInterfaceDevice.current().play(.success)
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if state == .success { state = .idle }
        } catch {
            let message = (error as? GateError)?.errorDescription
                ?? error.localizedDescription
            state = .failure(message)
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
