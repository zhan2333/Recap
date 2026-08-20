//
//  PDFViewController.swift
//  Recap
//
//  Created by Rio on 2026/8/20.
//

import UIKit
import PDFKit

/// Displays a compiled handout PDF with export and reveal actions.
final class PDFViewController: UIViewController {

    private let fileURL: URL
    private let pdfView = PDFView()

    init(fileURL: URL, title: String) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    /// Night rendering: invert luminance but keep hues (invert + 180° hue
    /// spin), so the warm paper turns dark and the signal color stays itself.
    private var invertsInDark = UserDefaults.standard.object(forKey: "pdfInvertsInDark") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(invertsInDark, forKey: "pdfInvertsInDark")
            applyAppearance()
        }
    }
    private var invertButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RecapTheme.paper

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.pageBreakMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        pdfView.document = PDFDocument(url: fileURL)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        invertButton = UIBarButtonItem(
            image: UIImage(systemName: "circle.lefthalf.filled"),
            primaryAction: UIAction { [weak self] _ in
                self?.invertsInDark.toggle()
            }
        )
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "square.and.arrow.up"),
                primaryAction: UIAction { [weak self] _ in self?.exportPDF() }
            ),
            invertButton,
        ]
        applyAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            applyAppearance()
        }
    }

    private func applyAppearance() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        invertButton.isHidden = !isDark
        if isDark && invertsInDark,
           let invert = CIFilter(name: "CIColorInvert"),
           let hue = CIFilter(name: "CIHueAdjust") {
            hue.setValue(CGFloat.pi, forKey: kCIInputAngleKey)
            pdfView.layer.filters = [invert, hue]
            // The filter inverts the backdrop too — feed it the inverse of the
            // dark canvas so it comes out right.
            pdfView.backgroundColor = UIColor(red: 0.878, green: 0.886, blue: 0.898, alpha: 1)
            invertButton.tintColor = RecapTheme.ink
        } else {
            pdfView.layer.filters = nil
            pdfView.backgroundColor = RecapTheme.canvas
            invertButton.tintColor = RecapTheme.quiet
        }
    }

    private func exportPDF() {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        present(picker, animated: true)
    }
}
