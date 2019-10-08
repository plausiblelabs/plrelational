//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit
import PLRelational

private let titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1)
private let textFont = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
private let titleColor = NSColor.black
private let textColor = NSColor.darkGray
private let highlightColor = NSColor.yellow

private extension String {
    func nsRange(from range: Range<Index>) -> NSRange {
        return NSRange(location: range.lowerBound.encodedOffset, length: range.upperBound.encodedOffset - range.lowerBound.encodedOffset)
    }
}

enum SearchResult {
    
    static let personNameAttribute: Attribute = "name"
    static let personBioAttribute: Attribute = "bio"
    
    /// Extracts the page title and content snippet from the given search result row and highlights matched terms,
    /// returning an NSAttributedString that can be used to display the search result in a table cell.
    static func highlightedString(from row: Row) -> NSAttributedString {
        func highlight(_ s: String, title: Bool) -> NSAttributedString {
            // Strip out newlines so that we have a better chance of fitting the full snippet in the available space
            let stripped = s.components(separatedBy: .newlines).joined(separator: " ")
            
            // Parse the snippet
            let snippet = RelationTextIndex.StructuredSnippet(rawString: stripped)
            
            // Set background color for matched text
            let attrStr = NSMutableAttributedString(string: snippet.string)
            for range in snippet.matches {
                attrStr.addAttribute(.backgroundColor, value: highlightColor, range: snippet.string.nsRange(from: range))
            }
            
            // Add ellipses as needed
            if snippet.ellipsisAtStart {
                attrStr.insert(NSAttributedString(string: "… "), at: 0)
            }
            if snippet.ellipsisAtEnd {
                attrStr.append(NSAttributedString(string: " …"))
            }
            
            // Apply font and foreground color attributes for the full string
            var attrs: [NSAttributedString.Key: Any] = [:]
            if title {
                attrs[.font] = titleFont
                attrs[.foregroundColor] = titleColor
            } else {
                attrs[.font] = textFont
                attrs[.foregroundColor] = textColor
            }
            attrStr.addAttributes(attrs, range: NSMakeRange(0, attrStr.length))
            
            return attrStr
        }
        
        let name: String = row[personNameAttribute].get()!
        let bio: String = row[personBioAttribute].get()!
        let attrStr = NSMutableAttributedString()
        
        /// Show person name in black with bold font
        attrStr.append(highlight(name, title: true))
        attrStr.append(NSAttributedString(string: "\n"))
        
        /// Show bio snippet in gray
        attrStr.append(highlight(bio, title: false))
        
        /// Add some breathing room
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4.0
        attrStr.addAttribute(.paragraphStyle, value: style, range: NSMakeRange(0, attrStr.length))
        
        return attrStr
    }
}
