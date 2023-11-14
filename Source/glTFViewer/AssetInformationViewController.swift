//
// Copyright 2023 The Khronos Group, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import UIKit

class SingleLineInfoTableViewCell: UITableViewCell {
    @IBOutlet weak var captionLabel: UILabel!
    @IBOutlet weak var contentsLabel: UILabel!

    public override var reuseIdentifier: String {
        return "SingleLineInfoTableViewCell"
    }
}

class MultipleLineInfoTableViewCell: UITableViewCell {
    @IBOutlet weak var captionLabel: UILabel!
    @IBOutlet weak var contentsTextView: UITextView!

    public override var reuseIdentifier: String {
        return "MultipleLineInfoTableViewCell"
    }
}

extension String {
    func height(withConstrainedWidth width: CGFloat, font: UIFont) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = self.boundingRect(with: constraintRect, 
                                            options: .usesLineFragmentOrigin,
                                            attributes: [.font: font], context: nil)
        return ceil(boundingBox.height)
    }
}

class AssetInformationViewController: UITableViewController {

    enum SectionIndex : Int {
        case metadata
        case statistics
        case copyright
    }

    var sectionContents : [[AssetInformationItem]] = []

    public var assetInfo: AssetInformation?

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        buildSectionContents()
    }

    private func buildSectionContents() {
        guard let assetInfo = self.assetInfo else { return }

        sectionContents = [ assetInfo.metadata, assetInfo.statistics ]
        
        if assetInfo.copyright.count > 0 {
            sectionContents.append(assetInfo.copyright)
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let info = sectionContents[indexPath.section][indexPath.row]

        let captionFont = UIFont.preferredFont(forTextStyle: .footnote)
        let contentsFont = UIFont.preferredFont(forTextStyle: .footnote)

        let defaultVerticalPadding = 8.0
        let expectedCellIndentWidth = 10.0
        let tableWidth = self.tableView.bounds.width
        let cellWidth = tableWidth - expectedCellIndentWidth

        switch (info.contentsPresentation) {
        case .singleLine:
            return (info.title?.height(withConstrainedWidth: cellWidth, font: captionFont) ?? captionFont.lineHeight) +
                   (defaultVerticalPadding * 2)
        case .multipleLine:
            return (info.title?.height(withConstrainedWidth: cellWidth, font: captionFont) ?? captionFont.lineHeight) +
                   (info.contents?.height(withConstrainedWidth: cellWidth, font: contentsFont) ?? 0) +
                   (defaultVerticalPadding * 3)
        }
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sectionContents.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return nil // "Metadata"
        case 1:
            return "Statistics"
        case 2:
            return "Copyright & License"
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sectionContents[section].count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let info = sectionContents[indexPath.section][indexPath.row]

        switch (info.contentsPresentation) {
        case .singleLine:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SingleLineInfoTableViewCell", for: indexPath)
            if let infoCell = cell as? SingleLineInfoTableViewCell {
                infoCell.captionLabel.text = info.title
                infoCell.contentsLabel.text = info.contents
                infoCell.contentsLabel.textAlignment = .right
            }
            return cell
        case .multipleLine:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MultipleLineInfoTableViewCell", for: indexPath)
            if let infoCell = cell as? MultipleLineInfoTableViewCell {
                infoCell.captionLabel.text = info.title
                infoCell.contentsTextView.text = info.contents
                infoCell.contentsTextView.textAlignment = .natural

                let padding = infoCell.contentsTextView.textContainer.lineFragmentPadding
                infoCell.contentsTextView.textContainerInset =  UIEdgeInsets(top: 0, left: -padding,
                                                                             bottom: 0, right: -padding)
            }
            return cell
        }
    }
}
