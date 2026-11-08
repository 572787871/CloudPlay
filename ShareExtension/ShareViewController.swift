import UIKit
import UniformTypeIdentifiers

/// Personal signing does not require App Groups. The system document picker
/// transfers received files into CloudPlay's visible Documents directory.
final class ShareViewController: UIViewController, UIDocumentPickerDelegate {
    private let status=UILabel()
    private var exportURL: URL?
    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor = .systemBackground
        status.numberOfLines=0;status.textAlignment = .center
        status.text="正在准备导入…";status.translatesAutoresizingMaskIntoConstraints=false
        let button=UIButton(type:.system);button.setTitle("保存到 CloudPlay 文件夹",for:.normal)
        button.addTarget(self,action:#selector(exportFile),for:.touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints=false
        let close=UIButton(type:.system);close.setTitle("取消",for:.normal);close.addTarget(self,action:#selector(cancel),for:.touchUpInside);close.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(status);view.addSubview(button);view.addSubview(close)
        NSLayoutConstraint.activate([status.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:24),status.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-24),status.centerYAnchor.constraint(equalTo:view.centerYAnchor,constant:-50),button.topAnchor.constraint(equalTo:status.bottomAnchor,constant:24),button.centerXAnchor.constraint(equalTo:view.centerXAnchor),close.topAnchor.constraint(equalTo:button.bottomAnchor,constant:20),close.centerXAnchor.constraint(equalTo:view.centerXAnchor)])
        prepare()
    }
    private func prepare() {
        guard let item=extensionContext?.inputItems.first as? NSExtensionItem, let provider=item.attachments?.first else {status.text="没有收到可导入的内容。";return}
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) {[weak self] value,error in
                guard let url=value as? URL else {self?.failed();return};self?.stage(url)
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier:UTType.url.identifier,options:nil) {[weak self] value,error in
                if let url=value as? URL {self?.stageText(url.absoluteString)} else {self?.failed()}
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier:UTType.plainText.identifier,options:nil) {[weak self] value,error in
                if let text=value as? String {self?.stageText(text)} else {self?.failed()}
            }
        } else if let type=provider.registeredTypeIdentifiers.first {
            provider.loadFileRepresentation(forTypeIdentifier:type) {[weak self] url,error in if let url {self?.stage(url)} else {self?.failed()} }
        } else {failed()}
    }
    private func stageText(_ text: String) {
        do {let target=FileManager.default.temporaryDirectory.appendingPathComponent("CloudPlay-链接.txt");try text.write(to:target,atomically:true,encoding:.utf8);ready(target)} catch {failed()}
    }
    private func stage(_ url: URL) {
        let accessible=url.startAccessingSecurityScopedResource();defer {if accessible {url.stopAccessingSecurityScopedResource()}}
        do {
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let target=folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at:url,to:target);ready(target)
        } catch {failed()}
    }
    private func ready(_ url: URL) {DispatchQueue.main.async {self.exportURL=url;self.status.text="下一步请选择：我的 iPhone → CloudPlay。\n保存后打开 CloudPlay，确认添加下载或上传文件。\n无需 App Groups 或付费开发者能力。"}}
    private func failed() {DispatchQueue.main.async {self.status.text="无法读取分享内容，请在文件 App 中使用“用 CloudPlay 打开”。"}}
    @objc private func exportFile() {
        guard let url=exportURL else{return}
        let picker=UIDocumentPickerViewController(forExporting:[url],asCopy:true);picker.delegate=self
        present(picker,animated:true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {extensionContext?.completeRequest(returningItems:nil)}
    @objc private func cancel() {extensionContext?.completeRequest(returningItems:nil)}
}
