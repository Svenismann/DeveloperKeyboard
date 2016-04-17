//
//  KeyboardViewController.swift
//  DevKey - Developer Keyboard
//
//  Created by sven forstner on 25.03.16.
//  Copyright © 2016 sven forstner. All rights reserved.
//

import UIKit
import Foundation

class KeyboardViewController: UIInputViewController, CharacterButtonDelegate, SuggestionButtonDelegate, TouchForwardingViewDelegate {
    
    // MARK: Constants
    
    private let mainCharacters = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]
    
    lazy var suggestionProvider: SuggestionProvider = SuggestionTree()
    
    lazy var languageProviders = CircularArray(items: [DefaultLanguageProvider(), HighLevelLanguageProvider()] as [LanguageProvider])
    
    private let spacing: CGFloat = 4.0
    private let predictiveTextBoxHeight: CGFloat = 30.0
    private var predictiveTextButtonWidth: CGFloat {
        return (view.frame.width - 4 * spacing) / 3.0
    }
    
    var keyboardHeightPortrait:CGFloat {
        var height = CGFloat()
        let screenSize = UIScreen.mainScreen().bounds
        
        if screenSize.width>screenSize.height {
            height = 165.0
        } else {
            height = 218.0
        }
        return height
        
    }
    
    private var keyWidthPortrait: CGFloat {
        return (view.frame.width - 11 * spacing) / 10.0
    }
    private var keyHeightPortrait: CGFloat {
        return (keyboardHeightPortrait - 5 * spacing - predictiveTextBoxHeight) / 4.0
    }
    
    
    // MARK: User interface
    
    private var swipeView: SwipeView!
    private var predictiveTextScrollView: PredictiveTextScrollView!
    private var suggestionButtons = [SuggestionButton]()
    
    private lazy var characterButtons: [[CharacterButton]] = [
        [],
        [],
        []
    ]
    private var shiftButton: KeyboardButtons!
    private var deleteButton: KeyboardButtons!
    private var tabButton: KeyboardButtons!
    private var nextKeyboardButton: KeyboardButtons!
    private var spaceButton: KeyboardButtons!
    private var returnButton: KeyboardButtons!
    private var currentLanguageLabel: UILabel!
    
    // MARK: Timers
    
    private var deleteButtonTimer: NSTimer?
    private var spaceButtonTimer: NSTimer?
    
    // MARK: Properties
    
    private var heightConstraint: NSLayoutConstraint!
    
    private var proxy: UITextDocumentProxy {
        return textDocumentProxy
    }
    
    private var lastWordTyped: String? {
        if let documentContextBeforeInput = proxy.documentContextBeforeInput as NSString? {
            let length = documentContextBeforeInput.length
            if length > 0 && NSCharacterSet.letterCharacterSet().characterIsMember(documentContextBeforeInput.characterAtIndex(length - 1)) {
                let components = documentContextBeforeInput.componentsSeparatedByCharactersInSet(NSCharacterSet.letterCharacterSet().invertedSet)
                return components[components.endIndex - 1]
            }
        }
        return nil
    }
    
    private var languageProvider: LanguageProvider = DefaultLanguageProvider() {
        didSet {
            for (rowIndex, row) in characterButtons.enumerate() {
                for (characterButtonIndex, characterButton) in row.enumerate() {
                    characterButton.secondaryCharacter = languageProvider.secondaryCharacters[rowIndex][characterButtonIndex]
                    characterButton.tertiaryCharacter = languageProvider.tertiaryCharacters[rowIndex][characterButtonIndex]
                }
            }
            currentLanguageLabel.text = languageProvider.language
            suggestionProvider.clear()
            suggestionProvider.loadWeightedStrings(languageProvider.suggestionDictionary)
        }
    }
    
    private enum ShiftMode {
        case Off, On, Caps
    }
    
    private var shiftMode: ShiftMode = .Off {
        didSet {
            shiftButton.selected = (shiftMode == .Caps)
            for row in characterButtons {
                for characterButton in row {
                    switch shiftMode {
                    case .Off:
                        characterButton.primaryLabel.text = characterButton.primaryCharacter.lowercaseString
                    case .On, .Caps:
                        characterButton.primaryLabel.text = characterButton.primaryCharacter.uppercaseString
                    }
                    
                }
            }
        }
    }
    
    // MARK: Constructors
    // FIXME: Uncomment init methods when crash bug is fixed. Also need to move languageProvider initialization to constructor to prevent unnecessary creation of two DefaultLanguageProvider instances.
    //    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
    //        self.shiftMode = .Off
    //        self.languageProvider = languageProviders.currentItem!
    //        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    //    }
    //
    //    required init(coder aDecoder: NSCoder) {
    //        fatalError("init(coder:) has not been implemented")
    //    }
    
    // MARK: Overridden methods
    
    //    override func loadView() {
    //        let screenRect = UIScreen.mainScreen().bounds
    //        self.view = TouchForwardingView(frame: CGRectMake(0.0, predictiveTextBoxHeight, screenRect.width, keyboardHeight - predictiveTextBoxHeight), delegate: self)
    //    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 237.0/255, green: 237.0/255, blue: 237.0/255, alpha: 1)
        heightConstraint = NSLayoutConstraint(item: self.view, attribute: .Height, relatedBy: .Equal, toItem: nil, attribute: .NotAnAttribute, multiplier: 0.0, constant: self.keyboardHeightPortrait)
        initializeKeyboard()
    }
    
    
    
    override func viewWillAppear(animated: Bool) {
        initializeKeyboard()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        initializeKeyboard()
        
        
    }
    
    override func didRotateFromInterfaceOrientation(fromInterfaceOrientation: UIInterfaceOrientation) {
        initializeKeyboard()
        
    }
    
    override func viewDidLayoutSubviews() { // so that this will be called last.
        self.view.addConstraint(NSLayoutConstraint(item: self.view, attribute: .Height, relatedBy: .Equal, toItem: nil, attribute: .NotAnAttribute, multiplier: 1.0, constant: 700))
    }
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
        view.removeConstraint(heightConstraint)
        heightConstraint.constant = keyboardHeightPortrait
        view.addConstraint(heightConstraint)
        
    }
    
    // MARK: Event handlers
    
    func shiftButtonPressed(sender: KeyboardButtons) {
        switch shiftMode {
        case .Off:
            shiftMode = .On
        case .On:
            shiftMode = .Caps
        case .Caps:
            shiftMode = .Off
        }
    }
    
    func deleteButtonPressed(sender: KeyboardButtons) {
        switch proxy.documentContextBeforeInput {
        case let s where s?.hasSuffix("    ") == true: // Cursor in front of tab, so delete tab.
            for _ in 0..<4 { // TODO: Update to use tab setting.
                proxy.deleteBackward()
            }
        default:
            proxy.deleteBackward()
        }
        updateSuggestions()
    }
    
    func handleLongPressForDeleteButtonWithGestureRecognizer(gestureRecognizer: UILongPressGestureRecognizer) {
        switch gestureRecognizer.state {
        case .Began:
            if deleteButtonTimer == nil {
                deleteButtonTimer = NSTimer(timeInterval: 0.1, target: self, selector: #selector(KeyboardViewController.handleDeleteButtonTimerTick(_:)), userInfo: nil, repeats: true)
                deleteButtonTimer!.tolerance = 0.01
                NSRunLoop.mainRunLoop().addTimer(deleteButtonTimer!, forMode: NSDefaultRunLoopMode)
            }
        default:
            deleteButtonTimer?.invalidate()
            deleteButtonTimer = nil
            updateSuggestions()
        }
    }
    
    func handleSwipeLeftForDeleteButtonWithGestureRecognizer(gestureRecognizer: UISwipeGestureRecognizer) {
        // TODO: Figure out an implementation that doesn't use bridgeToObjectiveC, in case of funny unicode characters.
        if let documentContextBeforeInput = proxy.documentContextBeforeInput as NSString? {
            if documentContextBeforeInput.length > 0 {
                var charactersToDelete = 0
                switch documentContextBeforeInput {
                case let s where NSCharacterSet.letterCharacterSet().characterIsMember(s.characterAtIndex(s.length - 1)): // Cursor in front of letter, so delete up to first non-letter character.
                    let range = documentContextBeforeInput.rangeOfCharacterFromSet(NSCharacterSet.letterCharacterSet().invertedSet, options: .BackwardsSearch)
                    if range.location != NSNotFound {
                        charactersToDelete = documentContextBeforeInput.length - range.location - 1
                    } else {
                        charactersToDelete = documentContextBeforeInput.length
                    }
                case let s where s.hasSuffix(" "): // Cursor in front of whitespace, so delete up to first non-whitespace character.
                    let range = documentContextBeforeInput.rangeOfCharacterFromSet(NSCharacterSet.whitespaceCharacterSet().invertedSet, options: .BackwardsSearch)
                    if range.location != NSNotFound {
                        charactersToDelete = documentContextBeforeInput.length - range.location - 1
                    } else {
                        charactersToDelete = documentContextBeforeInput.length
                    }
                default: // Just delete last character.
                    charactersToDelete = 1
                }
                
                for _ in 0..<charactersToDelete {
                    proxy.deleteBackward()
                }
            }
        }
        updateSuggestions()
    }
    
    func handleDeleteButtonTimerTick(timer: NSTimer) {
        proxy.deleteBackward()
    }
    
    func tabButtonPressed(sender: KeyboardButtons) {
        for _ in 0..<4 { // TODO: Update to use tab setting.
            proxy.insertText(" ")
        }
    }
    
    func spaceButtonPressed(sender: KeyboardButtons) {
        for suffix in languageProvider.autocapitalizeAfter {
            if proxy.documentContextBeforeInput!.hasSuffix(suffix) {
                shiftMode = .On
            }
        }
        proxy.insertText(" ")
        updateSuggestions()
    }
    
    func handleLongPressForSpaceButtonWithGestureRecognizer(gestureRecognizer: UISwipeGestureRecognizer) {
        switch gestureRecognizer.state {
        case .Began:
            if spaceButtonTimer == nil {
                spaceButtonTimer = NSTimer(timeInterval: 0.1, target: self, selector: #selector(KeyboardViewController.handleSpaceButtonTimerTick(_:)), userInfo: nil, repeats: true)
                spaceButtonTimer!.tolerance = 0.01
                NSRunLoop.mainRunLoop().addTimer(spaceButtonTimer!, forMode: NSDefaultRunLoopMode)
            }
        default:
            spaceButtonTimer?.invalidate()
            spaceButtonTimer = nil
            updateSuggestions()
        }
    }
    
    func handleSpaceButtonTimerTick(timer: NSTimer) {
        proxy.insertText(" ")
    }
    
    func handleSwipeLeftForSpaceButtonWithGestureRecognizer(gestureRecognizer: UISwipeGestureRecognizer) {
        UIView.animateWithDuration(0.1, animations: {
            self.moveButtonLabels(-self.keyWidthPortrait)
            }, completion: {
                (success: Bool) -> Void in
                self.languageProviders.increment()
                self.languageProvider = self.languageProviders.currentItem!
                self.moveButtonLabels(self.keyWidthPortrait * 2.0)
                UIView.animateWithDuration(0.1) {
                    self.moveButtonLabels(-self.keyWidthPortrait)
                }
            }
        )
    }
    
    func handleSwipeRightForSpaceButtonWithGestureRecognizer(gestureRecognizer: UISwipeGestureRecognizer) {
        UIView.animateWithDuration(0.1, animations: {
            self.moveButtonLabels(self.keyWidthPortrait)
            }, completion: {
                (success: Bool) -> Void in
                self.languageProviders.decrement()
                self.languageProvider = self.languageProviders.currentItem!
                self.moveButtonLabels(-self.keyWidthPortrait * 2.0)
                UIView.animateWithDuration(0.1) {
                    self.moveButtonLabels(self.keyWidthPortrait)
                }
            }
        )
    }
    
    func returnButtonPressed(sender: KeyboardButtons) {
        proxy.insertText("\n")
        updateSuggestions()
    }
    
    // MARK: CharacterButtonDelegate methods
    
    func handlePressForCharacterButton(button: CharacterButton) {
        switch shiftMode {
        case .Off:
            proxy.insertText(button.primaryCharacter.lowercaseString)
        case .On:
            proxy.insertText(button.primaryCharacter.uppercaseString)
            shiftMode = .Off
        case .Caps:
            proxy.insertText(button.primaryCharacter.uppercaseString)
        }
        updateSuggestions()
    }
    
    func handleSwipeUpForButton(button: CharacterButton) {
        proxy.insertText(button.secondaryCharacter)
        if button.secondaryCharacter.characters.count > 1 {
            proxy.insertText(" ")
        }
        updateSuggestions()
    }
    
    func handleSwipeDownForButton(button: CharacterButton) {
        proxy.insertText(button.tertiaryCharacter)
        if button.tertiaryCharacter.characters.count > 1 {
            proxy.insertText(" ")
        }
        updateSuggestions()
    }
    
    // MARK: SuggestionButtonDelegate methods
    
    func handlePressForSuggestionButton(button: SuggestionButton) {
        if let lastWord = lastWordTyped {
            for _ in lastWord.characters {
                proxy.deleteBackward()
            }
            proxy.insertText(button.title + " ")
            for suggestionButton in suggestionButtons {
                suggestionButton.removeFromSuperview()
            }
        }
    }
    
    // MARK: TouchForwardingViewDelegate methods
    
    // TODO: Get this method to properly provide the desired behaviour.
    func viewForHitTestWithPoint(point: CGPoint, event: UIEvent?, superResult: UIView?) -> UIView? {
        for subview in view.subviews {
            let convertPoint = subview.convertPoint(point, fromView: view)
            if subview is KeyboardButtons && subview.pointInside(convertPoint, withEvent: event) {
                return subview
            }
        }
        return swipeView
    }
    
    // MARK: Helper methods
    
    private func initializeKeyboard() {
        for subview in self.view.subviews {
            subview.removeFromSuperview() // Remove all buttons and gesture recognizers when view is recreated during orientation changes.
        }
        
        addPredictiveTextScrollView()
        addShiftButton()
        addDeleteButton()
        addTabButton()
        addNextKeyboardButton()
        addSpaceButton()
        addReturnButton()
        addCharacterButtons()
        addSwipeView()
        
        keyboardHeightPortrait
    }
    
    private func addPredictiveTextScrollView() {
        predictiveTextScrollView = PredictiveTextScrollView(frame: CGRectMake(0.0, 0.0, self.view.frame.width, predictiveTextBoxHeight))
        self.view.addSubview(predictiveTextScrollView)
    }
    
    private func addShiftButton() {
        shiftButton = KeyboardButtons(frame: CGRectMake(spacing, keyHeightPortrait * 2.0 + spacing * 3.0 + predictiveTextBoxHeight, keyWidthPortrait * 1.5 + spacing * 0.5, keyHeightPortrait))
        shiftButton.setTitle("\u{000021E7}", forState: .Normal)
        shiftButton.addTarget(self, action: #selector(KeyboardViewController.shiftButtonPressed(_:)), forControlEvents: .TouchUpInside)
        self.view.addSubview(shiftButton)
    }
    
    private func addDeleteButton() {
        deleteButton = KeyboardButtons(frame: CGRectMake(keyWidthPortrait * 8.5 + spacing * 9.5, keyHeightPortrait * 2.0 + spacing * 3.0 + predictiveTextBoxHeight, keyWidthPortrait * 1.5, keyHeightPortrait))
        deleteButton.setTitle("\u{0000232B}", forState: .Normal)
        deleteButton.addTarget(self, action: #selector(KeyboardViewController.deleteButtonPressed(_:)), forControlEvents: .TouchUpInside)
        self.view.addSubview(deleteButton)
        
        let deleteButtonLongPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(KeyboardViewController.handleLongPressForDeleteButtonWithGestureRecognizer(_:)))
        deleteButton.addGestureRecognizer(deleteButtonLongPressGestureRecognizer)
        
        let deleteButtonSwipeLeftGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(KeyboardViewController.handleSwipeLeftForDeleteButtonWithGestureRecognizer(_:)))
        deleteButtonSwipeLeftGestureRecognizer.direction = .Left
        deleteButton.addGestureRecognizer(deleteButtonSwipeLeftGestureRecognizer)
    }
    
    private func addTabButton() {
        tabButton = KeyboardButtons(frame: CGRectMake(spacing, keyHeightPortrait * 3.0 + spacing * 4.0 + predictiveTextBoxHeight, keyWidthPortrait * 1.5 + spacing * 0.5, keyHeightPortrait))
        tabButton.setTitle("tab", forState: .Normal)
        tabButton.addTarget(self, action: #selector(KeyboardViewController.tabButtonPressed(_:)), forControlEvents: .TouchUpInside)
        self.view.addSubview(tabButton)
    }
    
    private func addNextKeyboardButton() {
        nextKeyboardButton = KeyboardButtons(frame: CGRectMake(keyWidthPortrait * 1.5 + spacing * 2.5, keyHeightPortrait * 3.0 + spacing * 4.0 + predictiveTextBoxHeight, keyWidthPortrait, keyHeightPortrait))
        nextKeyboardButton.setTitle("\u{0001F310}", forState: .Normal)
        nextKeyboardButton.addTarget(self, action: #selector(UIInputViewController.advanceToNextInputMode), forControlEvents: .TouchUpInside)
        self.view.addSubview(nextKeyboardButton)
    }
    
    private func addSpaceButton() {
        spaceButton = KeyboardButtons(frame: CGRectMake(keyWidthPortrait * 2.5 + spacing * 3.5, keyHeightPortrait * 3.0 + spacing * 4.0 + predictiveTextBoxHeight, keyWidthPortrait * 5.0 + spacing * 4.0, keyHeightPortrait))
        spaceButton.addTarget(self, action: #selector(KeyboardViewController.spaceButtonPressed(_:)), forControlEvents: .TouchUpInside)
        self.view.addSubview(spaceButton)
        
        currentLanguageLabel = UILabel(frame: CGRectMake(0.0, 0.0, spaceButton.frame.width, spaceButton.frame.height * 0.33))
        currentLanguageLabel.font = UIFont(name: "HelveticaNeue", size: 12.0)
        currentLanguageLabel.adjustsFontSizeToFitWidth = true
        currentLanguageLabel.textColor = UIColor(white: 187.0/255, alpha: 1)
        currentLanguageLabel.textAlignment = .Center
        currentLanguageLabel.text = "\(languageProvider.language)"
        spaceButton.addSubview(currentLanguageLabel)
        
        let spaceButtonLongPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(KeyboardViewController.handleLongPressForSpaceButtonWithGestureRecognizer(_:)))
        spaceButton.addGestureRecognizer(spaceButtonLongPressGestureRecognizer)
        
        let spaceButtonSwipeLeftGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(KeyboardViewController.handleSwipeLeftForSpaceButtonWithGestureRecognizer(_:)))
        spaceButtonSwipeLeftGestureRecognizer.direction = .Left
        spaceButton.addGestureRecognizer(spaceButtonSwipeLeftGestureRecognizer)
        
        let spaceButtonSwipeRightGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(KeyboardViewController.handleSwipeRightForSpaceButtonWithGestureRecognizer(_:)))
        spaceButtonSwipeRightGestureRecognizer.direction = .Right
        spaceButton.addGestureRecognizer(spaceButtonSwipeRightGestureRecognizer)
    }
    
    private func addReturnButton() {
        returnButton = KeyboardButtons(frame: CGRectMake(keyWidthPortrait * 7.5 + spacing * 8.5, keyHeightPortrait * 3.0 + spacing * 4.0 + predictiveTextBoxHeight, keyWidthPortrait * 2.5 + spacing, keyHeightPortrait))
        returnButton.setTitle("\u{000023CE}", forState: .Normal)
        returnButton.addTarget(self, action: #selector(KeyboardViewController.returnButtonPressed(_:)), forControlEvents: .TouchUpInside)
        self.view.addSubview(returnButton)
    }
    
    private func addCharacterButtons() {
        characterButtons = [
            [],
            [],
            []
        ] // Clear characterButtons array.
        
        var y = spacing + predictiveTextBoxHeight
        for (rowIndex, row) in mainCharacters.enumerate() {
            var x: CGFloat
            switch rowIndex {
            case 1:
                x = spacing * 1.5 + keyWidthPortrait * 0.5
            case 2:
                x = spacing * 2.5 + keyWidthPortrait * 1.5
            default:
                x = spacing
            }
            for (keyIndex, key) in row.enumerate() {
                let characterButton = CharacterButton(frame: CGRectMake(x, y, keyWidthPortrait, keyHeightPortrait), primaryCharacter: key, secondaryCharacter: languageProvider.secondaryCharacters[rowIndex][keyIndex], tertiaryCharacter: languageProvider.tertiaryCharacters[rowIndex][keyIndex], delegate: self)
                self.view.addSubview(characterButton)
                characterButtons[rowIndex].append(characterButton)
                x += keyWidthPortrait + spacing
            }
            y += keyHeightPortrait + spacing
        }
    }
    
    private func addSwipeView() {
        swipeView = SwipeView(containerView: view, topOffset: predictiveTextBoxHeight)
        view.addSubview(swipeView)
    }
    
    private func moveButtonLabels(dx: CGFloat) {
        for (_, row) in characterButtons.enumerate() {
            for (_, characterButton) in row.enumerate() {
                characterButton.secondaryLabel.frame.offsetInPlace(dx: dx, dy: 0.0)
                characterButton.tertiaryLabel.frame.offsetInPlace(dx: dx, dy: 0.0)
            }
        }
        currentLanguageLabel.frame.offsetInPlace(dx: dx, dy: 0.0)
    }
    
    private func updateSuggestions() {
        for suggestionButton in suggestionButtons {
            suggestionButton.removeFromSuperview()
        }
        
        if let lastWord = lastWordTyped {
            var x = spacing
            for suggestion in suggestionProvider.suggestionsForPrefix(lastWord) {
                let suggestionButton = SuggestionButton(frame: CGRectMake(x, 0.0, predictiveTextButtonWidth, predictiveTextBoxHeight), title: suggestion, delegate: self)
                predictiveTextScrollView?.addSubview(suggestionButton)
                suggestionButtons.append(suggestionButton)
                x += predictiveTextButtonWidth + spacing
            }
            predictiveTextScrollView!.contentSize = CGSizeMake(x, predictiveTextBoxHeight)
        }
    }
}