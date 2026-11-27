import UIKit
import Capacitor

// רושם את הפלאגין של סט (Health, מסך נעילה, ווידג'ט) לפני שהאתר נטען
class SetBridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(SetNativePlugin())
    }
}
