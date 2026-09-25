import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    private var privacyOverlay: UIView?

    override func sceneWillResignActive(_ scene: UIScene) {
        super.sceneWillResignActive(scene)
        guard let windowScene = scene as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
                  ?? windowScene.windows.first
        else { return }

        if privacyOverlay != nil { return }

        let overlay = UIView(frame: window.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.black

        let label = UILabel()
        label.text = "Conductore"
        label.textColor = UIColor.white
        label.font = UIFont.systemFont(ofSize: 28, weight: .heavy)
        label.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])

        window.addSubview(overlay)
        privacyOverlay = overlay
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)
        privacyOverlay?.removeFromSuperview()
        privacyOverlay = nil
    }
}
