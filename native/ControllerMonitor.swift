import Foundation
import GameController

final class ControllerMonitor {
    var onPress: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var pressed = Set<ObjectIdentifier>()
    private var buttons: [ObjectIdentifier: [GCControllerButtonInput]] = [:]

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.attach(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.detach(controller) }
        })
        GCController.controllers().forEach(attach)
    }

    private func attach(_ controller: GCController) {
        detach(controller)
        var inputs: [GCControllerButtonInput] = []
        if let pad = controller.extendedGamepad {
            inputs = [pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY, pad.leftShoulder, pad.rightShoulder,
                      pad.leftTrigger, pad.rightTrigger, pad.buttonMenu,
                      pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right,
                      pad.leftThumbstick.up, pad.leftThumbstick.down, pad.leftThumbstick.left, pad.leftThumbstick.right,
                      pad.rightThumbstick.up, pad.rightThumbstick.down, pad.rightThumbstick.left, pad.rightThumbstick.right]
            inputs += [pad.buttonOptions, pad.buttonHome, pad.leftThumbstickButton, pad.rightThumbstickButton].compactMap { $0 }
        } else if let pad = controller.microGamepad {
            inputs = [pad.buttonA, pad.buttonX, pad.buttonMenu, pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right]
        }
        buttons[ObjectIdentifier(controller)] = inputs
        for button in inputs {
            let key = ObjectIdentifier(button)
            button.valueChangedHandler = { [weak self] _, value, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if value > 0.5 {
                        if self.pressed.insert(key).inserted { self.onPress?() }
                    } else { self.pressed.remove(key) }
                }
            }
        }
    }

    private func detach(_ controller: GCController) {
        for button in buttons.removeValue(forKey: ObjectIdentifier(controller)) ?? [] {
            pressed.remove(ObjectIdentifier(button)); button.valueChangedHandler = nil
        }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        GCController.controllers().forEach(detach)
        pressed.removeAll()
    }
}
