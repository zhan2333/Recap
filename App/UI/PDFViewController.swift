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

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in self?.exportPDF() }
        )
    }

    private func exportPDF() {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
        present(picker, animated: true)
    }
}
