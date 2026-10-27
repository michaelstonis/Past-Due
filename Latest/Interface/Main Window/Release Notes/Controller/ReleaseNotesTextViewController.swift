//
//  ReleaseNotesContentViewController.swift
//  Latest
//
//  Created by Max Langer on 12.08.18.
//  Copyright © 2018 Max Langer. All rights reserved.
//

import Cocoa

fileprivate let ReleaseNotesTextParagraphCellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "ReleaseNotesTextParagraphCellIdentifier")

/// The controller displaying the actual release notes
class ReleaseNotesTextViewController: NSViewController {

	/// The inset of the text
	let contentInset: CGFloat = 14
	
    /// The view displaying the release notes
    @IBOutlet var textView: NSTextView!
    
    /// Updates the view with the given release notes
    func set(_ string: NSAttributedString) {
        // Format the release notes
        let text = self.format(string)
        
        self.textView.textStorage?.setAttributedString(text)
    }
    
    /// Updates the text views scroll insets
    func updateInsets(with inset: CGFloat) {
        let scrollView = self.textView.enclosingScrollView
        
        scrollView?.automaticallyAdjustsContentInsets = false
        scrollView?.contentInsets = NSEdgeInsetsMake(inset + contentInset, contentInset, contentInset, contentInset)
		scrollView?.scrollerInsets = NSEdgeInsetsMake(-contentInset, -contentInset, -contentInset, -contentInset)
        
        self.view.layout()
        scrollView?.documentView?.scroll(CGPoint(x: 0, y: -inset * 2))
    }
    
    // MARK: - Private Methods
    
    /**
     This method modifies the release notes to make them look uniform.
     All custom fonts and font sizes are removed for a more unified look. Specific styles like bold or italic parts as well as links are preserved.
     - parameter attributedString: The string to be formatted
     - returns: The formatted string
     */
    func format(_ attributedString: NSAttributedString) -> NSAttributedString {
        let string = NSMutableAttributedString(attributedString: attributedString)
        let textRange = NSMakeRange(0, attributedString.length)
        let defaultFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        
        // Fix foreground color
        string.removeAttribute(.foregroundColor, range: textRange)
        string.addAttribute(.foregroundColor, value: NSColor.labelColor, range: textRange)
		
		// Remove background color
		string.removeAttribute(.backgroundColor, range: textRange)
        
		// Remove shadows
		string.removeAttribute(.shadow, range: textRange)
		
        // Reset font
        string.removeAttribute(.font, range: textRange)
        string.addAttribute(.font, value: defaultFont, range: textRange)
        
        // Copy traits like italic and bold, preserving relative heading hierarchy
        var majorHeadingRanges = [NSRange]()
        var minorHeadingRanges = [NSRange]()
        attributedString.enumerateAttribute(NSAttributedString.Key.font, in: textRange, options: .reverse) { (fontObject, range, stopPointer) in
            guard let font = fontObject as? NSFont else { return }
            
            let traits = font.fontDescriptor.symbolicTraits
            let pStyle = attributedString.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let isStandaloneSubheading = traits.contains(.bold) && (pStyle?.paragraphSpacing ?? 0) > 12 && font.pointSize < 13.5 && (pStyle?.headIndent ?? 0) == 0
            
            // NSAttributedString(html:) uses 12pt for body/h4, 14pt for h3, 18pt for h2, 24pt for h1
            if font.pointSize >= 22 {
                // h1: prominent version/release title
                let h1Font = NSFont.systemFont(ofSize: defaultFont.pointSize + 6, weight: .bold)
                string.addAttribute(.font, value: h1Font, range: range)
                majorHeadingRanges.append(range)
            } else if font.pointSize >= 16 {
                // h2: prominent version/section header
                let h2Font = NSFont.systemFont(ofSize: defaultFont.pointSize + 4.5, weight: .bold)
                string.addAttribute(.font, value: h2Font, range: range)
                majorHeadingRanges.append(range)
            } else if font.pointSize >= 13.5 {
                // h3: section subheader
                let h3Font = NSFont.systemFont(ofSize: defaultFont.pointSize + 1.5, weight: .semibold)
                string.addAttribute(.font, value: h3Font, range: range)
                minorHeadingRanges.append(range)
            } else if isStandaloneSubheading {
                // h4: category label (e.g. "New and Improved:", "Bug Fixes:")
                let h4Font = NSFont.systemFont(ofSize: defaultFont.pointSize, weight: .semibold)
                string.addAttribute(.font, value: h4Font, range: range)
                string.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                minorHeadingRanges.append(range)
            } else {
                let fontDescriptor = defaultFont.fontDescriptor.withSymbolicTraits(traits)
                if let mappedFont = NSFont(descriptor: fontDescriptor, size: defaultFont.pointSize) {
                    string.addAttribute(.font, value: mappedFont, range: range)
                }
            }
        }
        
        // Normalize paragraph spacing and strip duplicate NSTextList descriptors
        attributedString.enumerateAttribute(.paragraphStyle, in: textRange, options: []) { (styleObject, range, _) in
            guard let style = styleObject as? NSParagraphStyle,
                  let mutableStyle = style.mutableCopy() as? NSMutableParagraphStyle else {
                return
            }
            
            let isListParagraph = !style.textLists.isEmpty || style.headIndent > 0
            if !style.textLists.isEmpty {
                mutableStyle.textLists = []
            }
            
            let isMajorHeading = majorHeadingRanges.contains { NSIntersectionRange($0, range).length > 0 }
            let isMinorHeading = minorHeadingRanges.contains { NSIntersectionRange($0, range).length > 0 }
            if isMajorHeading {
                // Add generous separation above subsequent version headings and keep them anchored to their section
                mutableStyle.paragraphSpacingBefore = range.location == 0 ? 2 : max(style.paragraphSpacingBefore, 22)
                mutableStyle.paragraphSpacing = 6
            } else if isMinorHeading {
                mutableStyle.paragraphSpacingBefore = range.location == 0 ? 0 : max(style.paragraphSpacingBefore, 10)
                mutableStyle.paragraphSpacing = 4
            } else if isListParagraph {
                mutableStyle.paragraphSpacing = max(style.paragraphSpacing, 4)
            } else if style.paragraphSpacing > 12 {
                mutableStyle.paragraphSpacingBefore = range.location == 0 ? 0 : max(style.paragraphSpacingBefore, 6)
                mutableStyle.paragraphSpacing = 6
            }
            
            string.addAttribute(.paragraphStyle, value: mutableStyle, range: range)
        }
        
        return string
    }
    
}

extension ReleaseNotesTextViewController: ReleaseNotesContentProtocol {
    
    typealias ReleaseNotesContentController = ReleaseNotesTextViewController
    
    static var StoryboardIdentifier: String {
        return "ReleaseNotesTextViewControllerIdentifier"
    }
    
}
