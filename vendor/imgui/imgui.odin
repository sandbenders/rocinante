// SPDX-License-Identifier: 0BSD
//
// Dear ImGui v1.93.0 (MIT) and its SDL3 and SDL_GPU backends, as Odin. Made by tools/imgui from the
// JSON that dear_bindings v0.26 writes; do not edit it by hand.
package imgui

import sdl "vendor:sdl3"

when ODIN_OS == .Darwin || ODIN_OS == .FreeBSD {
	foreign import lib {"../../.cache/ui/libroci_ui.a", "system:c++"}
} else when ODIN_OS == .Linux || ODIN_OS == .OpenBSD {
	foreign import lib {"../../.cache/ui/libroci_ui.a", "system:stdc++"}
} else {
	foreign import lib "../../.cache/ui/roci_ui.lib"
}

DrawIdx :: u16
ID :: u32
S8 :: u8
U8 :: u8
S16 :: i16
U16 :: u16
S32 :: i32
U32 :: u32
S64 :: i64
U64 :: u64
Dir :: i32
Key :: i32
MouseSource :: i32
SortDirection :: U8
Col :: i32
Cond :: i32
DataType :: i32
MouseButton :: i32
MouseCursor :: i32
StyleVar :: i32
TableBgTarget :: i32
DrawFlags :: i32
DrawTextFlags :: i32
FontFlags :: i32
FontAtlasFlags :: i32
BackendFlags :: i32
ButtonFlags :: i32
ChildFlags :: i32
ColorEditFlags :: i32
ConfigFlags :: i32
ComboFlags :: i32
DragDropFlags :: i32
FocusedFlags :: i32
HoveredFlags :: i32
InputFlags :: i32
InputTextFlags :: i32
ItemFlags :: i32
KeyChord :: i32
ListClipperFlags :: i32
PopupFlags :: i32
MultiSelectFlags :: i32
SelectableFlags :: i32
SliderFlags :: i32
TabBarFlags :: i32
TabItemFlags :: i32
TableFlags :: i32
TableColumnFlags :: i32
TableRowFlags :: i32
TreeNodeFlags :: i32
ViewportFlags :: i32
WindowFlags :: i32
Wchar32 :: u32
Wchar16 :: u16
Wchar :: u16
SelectionUserData :: S64
TextureID :: U64
FontAtlasRectId :: i32
DrawListFlags :: DrawFlags
SDL_Event :: sdl.Event

WindowFlags_None :: 0
WindowFlags_NoTitleBar :: 1
WindowFlags_NoResize :: 2
WindowFlags_NoMove :: 4
WindowFlags_NoScrollbar :: 8
WindowFlags_NoScrollWithMouse :: 16
WindowFlags_NoCollapse :: 32
WindowFlags_AlwaysAutoResize :: 64
WindowFlags_NoBackground :: 128
WindowFlags_NoSavedSettings :: 256
WindowFlags_NoMouseInputs :: 512
WindowFlags_MenuBar :: 1024
WindowFlags_HorizontalScrollbar :: 2048
WindowFlags_NoFocusOnAppearing :: 4096
WindowFlags_NoBringToFrontOnFocus :: 8192
WindowFlags_AlwaysVerticalScrollbar :: 16384
WindowFlags_AlwaysHorizontalScrollbar :: 32768
WindowFlags_NoNavInputs :: 65536
WindowFlags_NoNavFocus :: 131072
WindowFlags_UnsavedDocument :: 262144
WindowFlags_NoNav :: 196608
WindowFlags_NoDecoration :: 43
WindowFlags_NoInputs :: 197120
WindowFlags_ChildWindow :: 16777216
WindowFlags_Tooltip :: 33554432
WindowFlags_Popup :: 67108864
WindowFlags_Modal :: 134217728
WindowFlags_ChildMenu :: 268435456
ChildFlags_None :: 0
ChildFlags_Borders :: 1
ChildFlags_AlwaysUseWindowPadding :: 2
ChildFlags_ResizeX :: 4
ChildFlags_ResizeY :: 8
ChildFlags_AutoResizeX :: 16
ChildFlags_AutoResizeY :: 32
ChildFlags_AlwaysAutoResize :: 64
ChildFlags_FrameStyle :: 128
ChildFlags_NavFlattened :: 256
ItemFlags_None :: 0
ItemFlags_NoTabStop :: 1
ItemFlags_NoNav :: 2
ItemFlags_NoNavDefaultFocus :: 4
ItemFlags_ButtonRepeat :: 8
ItemFlags_AutoClosePopups :: 16
ItemFlags_AllowDuplicateId :: 32
ItemFlags_Disabled :: 64
ItemFlags_LiveEditOnInputText :: 128
ItemFlags_LiveEditOnInputScalar :: 256
ItemFlags_LiveEditOnInput :: 384
ItemFlags_MixedValue :: 512
InputTextFlags_None :: 0
InputTextFlags_CharsDecimal :: 1
InputTextFlags_CharsHexadecimal :: 2
InputTextFlags_CharsScientific :: 4
InputTextFlags_CharsUppercase :: 8
InputTextFlags_CharsNoBlank :: 16
InputTextFlags_AllowTabInput :: 32
InputTextFlags_EnterReturnsTrue :: 64
InputTextFlags_EscapeClearsAll :: 128
InputTextFlags_CtrlEnterForNewLine :: 256
InputTextFlags_ReadOnly :: 512
InputTextFlags_Password :: 1024
InputTextFlags_AlwaysOverwrite :: 2048
InputTextFlags_AutoSelectAll :: 4096
InputTextFlags_ParseEmptyRefVal :: 8192
InputTextFlags_DisplayEmptyRefVal :: 16384
InputTextFlags_NoHorizontalScroll :: 32768
InputTextFlags_NoUndoRedo :: 65536
InputTextFlags_ElideLeft :: 131072
InputTextFlags_CallbackCompletion :: 262144
InputTextFlags_CallbackHistory :: 524288
InputTextFlags_CallbackAlways :: 1048576
InputTextFlags_CallbackCharFilter :: 2097152
InputTextFlags_CallbackResize :: 4194304
InputTextFlags_CallbackEdit :: 8388608
InputTextFlags_WordWrap :: 16777216
TreeNodeFlags_None :: 0
TreeNodeFlags_Selected :: 1
TreeNodeFlags_Framed :: 2
TreeNodeFlags_AllowOverlap :: 4
TreeNodeFlags_NoTreePushOnOpen :: 8
TreeNodeFlags_NoAutoOpenOnLog :: 16
TreeNodeFlags_DefaultOpen :: 32
TreeNodeFlags_OpenOnDoubleClick :: 64
TreeNodeFlags_OpenOnArrow :: 128
TreeNodeFlags_Leaf :: 256
TreeNodeFlags_Bullet :: 512
TreeNodeFlags_FramePadding :: 1024
TreeNodeFlags_SpanAvailWidth :: 2048
TreeNodeFlags_SpanFullWidth :: 4096
TreeNodeFlags_SpanLabelWidth :: 8192
TreeNodeFlags_SpanAllColumns :: 16384
TreeNodeFlags_LabelSpanAllColumns :: 32768
TreeNodeFlags_NavLeftJumpsToParent :: 131072
TreeNodeFlags_CollapsingHeader :: 26
TreeNodeFlags_DrawLinesNone :: 262144
TreeNodeFlags_DrawLinesFull :: 524288
TreeNodeFlags_DrawLinesToNodes :: 1048576
TreeNodeFlags_NavLeftJumpsBackHere :: 131072
PopupFlags_None :: 0
PopupFlags_MouseButtonLeft :: 4
PopupFlags_MouseButtonRight :: 8
PopupFlags_MouseButtonMiddle :: 12
PopupFlags_NoReopen :: 32
PopupFlags_NoOpenOverExistingPopup :: 128
PopupFlags_NoOpenOverItems :: 256
PopupFlags_AnyPopupId :: 1024
PopupFlags_AnyPopupLevel :: 2048
PopupFlags_AnyPopup :: 3072
PopupFlags_MouseButtonShift_ :: 2
PopupFlags_MouseButtonMask_ :: 12
PopupFlags_InvalidMask_ :: 3
SelectableFlags_None :: 0
SelectableFlags_NoAutoClosePopups :: 1
SelectableFlags_SpanAllColumns :: 2
SelectableFlags_AllowDoubleClick :: 4
SelectableFlags_Disabled :: 8
SelectableFlags_AllowOverlap :: 16
SelectableFlags_Highlight :: 32
SelectableFlags_SelectOnNav :: 64
SelectableFlags_DontClosePopups :: 1
ComboFlags_None :: 0
ComboFlags_PopupAlignLeft :: 1
ComboFlags_HeightSmall :: 2
ComboFlags_HeightRegular :: 4
ComboFlags_HeightLarge :: 8
ComboFlags_HeightLargest :: 16
ComboFlags_NoArrowButton :: 32
ComboFlags_NoPreview :: 64
ComboFlags_WidthFitPreview :: 128
ComboFlags_HeightMask_ :: 30
TabBarFlags_None :: 0
TabBarFlags_Reorderable :: 1
TabBarFlags_AutoSelectNewTabs :: 2
TabBarFlags_TabListPopupButton :: 4
TabBarFlags_NoCloseWithMiddleMouseButton :: 8
TabBarFlags_NoTabListScrollingButtons :: 16
TabBarFlags_NoTooltip :: 32
TabBarFlags_DrawSelectedOverline :: 64
TabBarFlags_FittingPolicyMixed :: 128
TabBarFlags_FittingPolicyShrink :: 256
TabBarFlags_FittingPolicyScroll :: 512
TabBarFlags_FittingPolicyMask_ :: 896
TabBarFlags_FittingPolicyDefault_ :: 128
TabBarFlags_FittingPolicyResizeDown :: 256
TabItemFlags_None :: 0
TabItemFlags_UnsavedDocument :: 1
TabItemFlags_SetSelected :: 2
TabItemFlags_NoCloseWithMiddleMouseButton :: 4
TabItemFlags_NoPushId :: 8
TabItemFlags_NoTooltip :: 16
TabItemFlags_NoReorder :: 32
TabItemFlags_Leading :: 64
TabItemFlags_Trailing :: 128
TabItemFlags_NoAssumedClosure :: 256
FocusedFlags_None :: 0
FocusedFlags_ChildWindows :: 1
FocusedFlags_RootWindow :: 2
FocusedFlags_AnyWindow :: 4
FocusedFlags_NoPopupHierarchy :: 8
FocusedFlags_RootAndChildWindows :: 3
HoveredFlags_None :: 0
HoveredFlags_ChildWindows :: 1
HoveredFlags_RootWindow :: 2
HoveredFlags_AnyWindow :: 4
HoveredFlags_NoPopupHierarchy :: 8
HoveredFlags_AllowWhenBlockedByPopup :: 32
HoveredFlags_AllowWhenBlockedByActiveItem :: 128
HoveredFlags_AllowWhenOverlappedByItem :: 256
HoveredFlags_AllowWhenOverlappedByWindow :: 512
HoveredFlags_AllowWhenDisabled :: 1024
HoveredFlags_NoNavOverride :: 2048
HoveredFlags_AllowWhenOverlapped :: 768
HoveredFlags_RectOnly :: 928
HoveredFlags_RootAndChildWindows :: 3
HoveredFlags_ForTooltip :: 4096
HoveredFlags_Stationary :: 8192
HoveredFlags_DelayNone :: 16384
HoveredFlags_DelayShort :: 32768
HoveredFlags_DelayNormal :: 65536
HoveredFlags_NoSharedDelay :: 131072
DragDropFlags_None :: 0
DragDropFlags_SourceNoPreviewTooltip :: 1
DragDropFlags_SourceNoDisableHover :: 2
DragDropFlags_SourceNoHoldToOpenOthers :: 4
DragDropFlags_SourceAllowNullID :: 8
DragDropFlags_SourceExtern :: 16
DragDropFlags_PayloadAutoExpire :: 32
DragDropFlags_PayloadNoCrossContext :: 64
DragDropFlags_PayloadNoCrossProcess :: 128
DragDropFlags_AcceptBeforeDelivery :: 1024
DragDropFlags_AcceptNoDrawDefaultRect :: 2048
DragDropFlags_AcceptNoPreviewTooltip :: 4096
DragDropFlags_AcceptDrawAsHovered :: 8192
DragDropFlags_AcceptPeekOnly :: 3072
DataType_S8 :: 0
DataType_U8 :: 1
DataType_S16 :: 2
DataType_U16 :: 3
DataType_S32 :: 4
DataType_U32 :: 5
DataType_S64 :: 6
DataType_U64 :: 7
DataType_Float :: 8
DataType_Double :: 9
DataType_Bool :: 10
DataType_String :: 11
DataType_COUNT :: 12
Dir_None :: -1
Dir_Left :: 0
Dir_Right :: 1
Dir_Up :: 2
Dir_Down :: 3
Dir_COUNT :: 4
SortDirection_None :: 0
SortDirection_Ascending :: 1
SortDirection_Descending :: 2
Key_None :: 0
Key_NamedKey_BEGIN :: 512
Key_Tab :: 512
Key_LeftArrow :: 513
Key_RightArrow :: 514
Key_UpArrow :: 515
Key_DownArrow :: 516
Key_PageUp :: 517
Key_PageDown :: 518
Key_Home :: 519
Key_End :: 520
Key_Insert :: 521
Key_Delete :: 522
Key_Backspace :: 523
Key_Space :: 524
Key_Enter :: 525
Key_Escape :: 526
Key_LeftCtrl :: 527
Key_LeftShift :: 528
Key_LeftAlt :: 529
Key_LeftSuper :: 530
Key_RightCtrl :: 531
Key_RightShift :: 532
Key_RightAlt :: 533
Key_RightSuper :: 534
Key_Menu :: 535
Key_0 :: 536
Key_1 :: 537
Key_2 :: 538
Key_3 :: 539
Key_4 :: 540
Key_5 :: 541
Key_6 :: 542
Key_7 :: 543
Key_8 :: 544
Key_9 :: 545
Key_A :: 546
Key_B :: 547
Key_C :: 548
Key_D :: 549
Key_E :: 550
Key_F :: 551
Key_G :: 552
Key_H :: 553
Key_I :: 554
Key_J :: 555
Key_K :: 556
Key_L :: 557
Key_M :: 558
Key_N :: 559
Key_O :: 560
Key_P :: 561
Key_Q :: 562
Key_R :: 563
Key_S :: 564
Key_T :: 565
Key_U :: 566
Key_V :: 567
Key_W :: 568
Key_X :: 569
Key_Y :: 570
Key_Z :: 571
Key_F1 :: 572
Key_F2 :: 573
Key_F3 :: 574
Key_F4 :: 575
Key_F5 :: 576
Key_F6 :: 577
Key_F7 :: 578
Key_F8 :: 579
Key_F9 :: 580
Key_F10 :: 581
Key_F11 :: 582
Key_F12 :: 583
Key_F13 :: 584
Key_F14 :: 585
Key_F15 :: 586
Key_F16 :: 587
Key_F17 :: 588
Key_F18 :: 589
Key_F19 :: 590
Key_F20 :: 591
Key_F21 :: 592
Key_F22 :: 593
Key_F23 :: 594
Key_F24 :: 595
Key_Apostrophe :: 596
Key_Comma :: 597
Key_Minus :: 598
Key_Period :: 599
Key_Slash :: 600
Key_Semicolon :: 601
Key_Equal :: 602
Key_LeftBracket :: 603
Key_Backslash :: 604
Key_RightBracket :: 605
Key_GraveAccent :: 606
Key_CapsLock :: 607
Key_ScrollLock :: 608
Key_NumLock :: 609
Key_PrintScreen :: 610
Key_Pause :: 611
Key_Keypad0 :: 612
Key_Keypad1 :: 613
Key_Keypad2 :: 614
Key_Keypad3 :: 615
Key_Keypad4 :: 616
Key_Keypad5 :: 617
Key_Keypad6 :: 618
Key_Keypad7 :: 619
Key_Keypad8 :: 620
Key_Keypad9 :: 621
Key_KeypadDecimal :: 622
Key_KeypadDivide :: 623
Key_KeypadMultiply :: 624
Key_KeypadSubtract :: 625
Key_KeypadAdd :: 626
Key_KeypadEnter :: 627
Key_KeypadEqual :: 628
Key_AppBack :: 629
Key_AppForward :: 630
Key_Oem102 :: 631
Key_GamepadStart :: 632
Key_GamepadBack :: 633
Key_GamepadFaceLeft :: 634
Key_GamepadFaceRight :: 635
Key_GamepadFaceUp :: 636
Key_GamepadFaceDown :: 637
Key_GamepadDpadLeft :: 638
Key_GamepadDpadRight :: 639
Key_GamepadDpadUp :: 640
Key_GamepadDpadDown :: 641
Key_GamepadL1 :: 642
Key_GamepadR1 :: 643
Key_GamepadL2 :: 644
Key_GamepadR2 :: 645
Key_GamepadL3 :: 646
Key_GamepadR3 :: 647
Key_GamepadLStickLeft :: 648
Key_GamepadLStickRight :: 649
Key_GamepadLStickUp :: 650
Key_GamepadLStickDown :: 651
Key_GamepadRStickLeft :: 652
Key_GamepadRStickRight :: 653
Key_GamepadRStickUp :: 654
Key_GamepadRStickDown :: 655
Key_MouseLeft :: 656
Key_MouseRight :: 657
Key_MouseMiddle :: 658
Key_MouseX1 :: 659
Key_MouseX2 :: 660
Key_MouseWheelX :: 661
Key_MouseWheelY :: 662
Key_ReservedForModCtrl :: 663
Key_ReservedForModShift :: 664
Key_ReservedForModAlt :: 665
Key_ReservedForModSuper :: 666
Key_NamedKey_END :: 667
Key_NamedKey_COUNT :: 155
Mod_None :: 0
Mod_Ctrl :: 4096
Mod_Shift :: 8192
Mod_Alt :: 16384
Mod_Super :: 32768
Mod_Mask_ :: 61440
Key_COUNT :: 667
Mod_Shortcut :: 4096
InputFlags_None :: 0
InputFlags_Repeat :: 1
InputFlags_RouteActive :: 1024
InputFlags_RouteFocused :: 2048
InputFlags_RouteGlobal :: 4096
InputFlags_RouteAlways :: 8192
InputFlags_RouteOverFocused :: 16384
InputFlags_RouteOverActive :: 32768
InputFlags_RouteUnlessBgFocused :: 65536
InputFlags_RouteFromRootWindow :: 131072
InputFlags_Tooltip :: 262144
ConfigFlags_None :: 0
ConfigFlags_NavEnableKeyboard :: 1
ConfigFlags_NavEnableGamepad :: 2
ConfigFlags_NoMouse :: 16
ConfigFlags_NoMouseCursorChange :: 32
ConfigFlags_NoKeyboard :: 64
ConfigFlags_IsSRGB :: 1048576
ConfigFlags_IsTouchScreen :: 2097152
ConfigFlags_NavEnableSetMousePos :: 4
ConfigFlags_NavNoCaptureKeyboard :: 8
BackendFlags_None :: 0
BackendFlags_HasGamepad :: 1
BackendFlags_HasMouseCursors :: 2
BackendFlags_HasSetMousePos :: 4
BackendFlags_RendererHasVtxOffset :: 8
BackendFlags_RendererHasTextures :: 16
Col_Text :: 0
Col_TextDisabled :: 1
Col_WindowBg :: 2
Col_ChildBg :: 3
Col_PopupBg :: 4
Col_Border :: 5
Col_BorderShadow :: 6
Col_FrameBg :: 7
Col_FrameBgHovered :: 8
Col_FrameBgActive :: 9
Col_TitleBg :: 10
Col_TitleBgActive :: 11
Col_TitleBgCollapsed :: 12
Col_MenuBarBg :: 13
Col_ScrollbarBg :: 14
Col_ScrollbarGrab :: 15
Col_ScrollbarGrabHovered :: 16
Col_ScrollbarGrabActive :: 17
Col_CheckMark :: 18
Col_CheckboxSelectedBg :: 19
Col_SliderGrab :: 20
Col_SliderGrabActive :: 21
Col_Button :: 22
Col_ButtonHovered :: 23
Col_ButtonActive :: 24
Col_Header :: 25
Col_HeaderHovered :: 26
Col_HeaderActive :: 27
Col_Separator :: 28
Col_SeparatorHovered :: 29
Col_SeparatorActive :: 30
Col_ResizeGrip :: 31
Col_ResizeGripHovered :: 32
Col_ResizeGripActive :: 33
Col_InputTextCursor :: 34
Col_TabHovered :: 35
Col_Tab :: 36
Col_TabSelected :: 37
Col_TabSelectedOverline :: 38
Col_TabDimmed :: 39
Col_TabDimmedSelected :: 40
Col_TabDimmedSelectedOverline :: 41
Col_PlotLines :: 42
Col_PlotLinesHovered :: 43
Col_PlotHistogram :: 44
Col_PlotHistogramHovered :: 45
Col_TableHeaderBg :: 46
Col_TableBorderStrong :: 47
Col_TableBorderLight :: 48
Col_TableRowBg :: 49
Col_TableRowBgAlt :: 50
Col_TextLink :: 51
Col_TextSelectedBg :: 52
Col_TreeLines :: 53
Col_DragDropTarget :: 54
Col_DragDropTargetBg :: 55
Col_UnsavedMarker :: 56
Col_NavCursor :: 57
Col_NavWindowingHighlight :: 58
Col_NavWindowingDimBg :: 59
Col_ModalWindowDimBg :: 60
Col_COUNT :: 61
Col_TabActive :: 37
Col_TabUnfocused :: 39
Col_TabUnfocusedActive :: 40
Col_NavHighlight :: 57
StyleVar_Alpha :: 0
StyleVar_DisabledAlpha :: 1
StyleVar_WindowPadding :: 2
StyleVar_WindowRounding :: 3
StyleVar_WindowBorderSize :: 4
StyleVar_WindowMinSize :: 5
StyleVar_WindowTitleAlign :: 6
StyleVar_ChildRounding :: 7
StyleVar_ChildBorderSize :: 8
StyleVar_PopupRounding :: 9
StyleVar_PopupBorderSize :: 10
StyleVar_FramePadding :: 11
StyleVar_FrameRounding :: 12
StyleVar_FrameBorderSize :: 13
StyleVar_ItemSpacing :: 14
StyleVar_ItemInnerSpacing :: 15
StyleVar_IndentSpacing :: 16
StyleVar_CellPadding :: 17
StyleVar_ScrollbarSize :: 18
StyleVar_ScrollbarRounding :: 19
StyleVar_ScrollbarPadding :: 20
StyleVar_GrabMinSize :: 21
StyleVar_GrabRounding :: 22
StyleVar_ImageRounding :: 23
StyleVar_ImageBorderSize :: 24
StyleVar_TabRounding :: 25
StyleVar_TabBorderSize :: 26
StyleVar_TabMinWidthBase :: 27
StyleVar_TabMinWidthShrink :: 28
StyleVar_TabBarBorderSize :: 29
StyleVar_TabBarOverlineSize :: 30
StyleVar_TableAngledHeadersAngle :: 31
StyleVar_TableAngledHeadersTextAlign :: 32
StyleVar_TreeLinesSize :: 33
StyleVar_TreeLinesRounding :: 34
StyleVar_MenuItemRounding :: 35
StyleVar_SelectableRounding :: 36
StyleVar_DragDropTargetRounding :: 37
StyleVar_ButtonTextAlign :: 38
StyleVar_SelectableTextAlign :: 39
StyleVar_SeparatorSize :: 40
StyleVar_SeparatorTextBorderSize :: 41
StyleVar_SeparatorTextAlign :: 42
StyleVar_SeparatorTextPadding :: 43
StyleVar_COUNT :: 44
ButtonFlags_None :: 0
ButtonFlags_MouseButtonLeft :: 1
ButtonFlags_MouseButtonRight :: 2
ButtonFlags_MouseButtonMiddle :: 4
ButtonFlags_MouseButtonMask_ :: 7
ButtonFlags_EnableNav :: 8
ButtonFlags_AllowOverlap :: 4096
ColorEditFlags_None :: 0
ColorEditFlags_NoAlpha :: 2
ColorEditFlags_NoPicker :: 4
ColorEditFlags_NoOptions :: 8
ColorEditFlags_NoSmallPreview :: 16
ColorEditFlags_NoInputs :: 32
ColorEditFlags_NoTooltip :: 64
ColorEditFlags_NoLabel :: 128
ColorEditFlags_NoSidePreview :: 256
ColorEditFlags_NoDragDrop :: 512
ColorEditFlags_NoBorder :: 1024
ColorEditFlags_NoColorMarkers :: 2048
ColorEditFlags_AlphaOpaque :: 4096
ColorEditFlags_AlphaNoBg :: 8192
ColorEditFlags_AlphaPreviewHalf :: 16384
ColorEditFlags_AlphaBar :: 262144
ColorEditFlags_HDR :: 524288
ColorEditFlags_DisplayRGB :: 1048576
ColorEditFlags_DisplayHSV :: 2097152
ColorEditFlags_DisplayHex :: 4194304
ColorEditFlags_Uint8 :: 8388608
ColorEditFlags_Float :: 16777216
ColorEditFlags_PickerHueBar :: 33554432
ColorEditFlags_PickerHueWheel :: 67108864
ColorEditFlags_PickerNoRotate :: 134217728
ColorEditFlags_InputRGB :: 268435456
ColorEditFlags_InputHSV :: 536870912
ColorEditFlags_DefaultOptions_ :: 311427072
ColorEditFlags_AlphaMask_ :: 28674
ColorEditFlags_DisplayMask_ :: 7340032
ColorEditFlags_DataTypeMask_ :: 25165824
ColorEditFlags_PickerMask_ :: 100663296
ColorEditFlags_InputMask_ :: 805306368
ColorEditFlags_AlphaPreview :: 0
SliderFlags_None :: 0
SliderFlags_Logarithmic :: 32
SliderFlags_NoRoundToFormat :: 64
SliderFlags_NoInput :: 128
SliderFlags_WrapAround :: 256
SliderFlags_ClampOnInput :: 512
SliderFlags_ClampZeroRange :: 1024
SliderFlags_NoSpeedTweaks :: 2048
SliderFlags_ColorMarkers :: 4096
SliderFlags_AlwaysClamp :: 1536
SliderFlags_InvalidMask_ :: 1879048207
MouseButton_Left :: 0
MouseButton_Right :: 1
MouseButton_Middle :: 2
MouseButton_COUNT :: 5
MouseCursor_None :: -1
MouseCursor_Arrow :: 0
MouseCursor_TextInput :: 1
MouseCursor_ResizeAll :: 2
MouseCursor_ResizeNS :: 3
MouseCursor_ResizeEW :: 4
MouseCursor_ResizeNESW :: 5
MouseCursor_ResizeNWSE :: 6
MouseCursor_Hand :: 7
MouseCursor_Wait :: 8
MouseCursor_Progress :: 9
MouseCursor_NotAllowed :: 10
MouseCursor_COUNT :: 11
MouseSource_Mouse :: 0
MouseSource_TouchScreen :: 1
MouseSource_Pen :: 2
MouseSource_COUNT :: 3
Cond_None :: 0
Cond_Always :: 1
Cond_Once :: 2
Cond_FirstUseEver :: 4
Cond_Appearing :: 8
TableFlags_None :: 0
TableFlags_Resizable :: 1
TableFlags_Reorderable :: 2
TableFlags_Hideable :: 4
TableFlags_Sortable :: 8
TableFlags_NoSavedSettings :: 16
TableFlags_ContextMenuInBody :: 32
TableFlags_RowBg :: 64
TableFlags_BordersInnerH :: 128
TableFlags_BordersOuterH :: 256
TableFlags_BordersInnerV :: 512
TableFlags_BordersOuterV :: 1024
TableFlags_BordersH :: 384
TableFlags_BordersV :: 1536
TableFlags_BordersInner :: 640
TableFlags_BordersOuter :: 1280
TableFlags_Borders :: 1920
TableFlags_NoBordersInBody :: 2048
TableFlags_NoBordersInBodyUntilResize :: 4096
TableFlags_SizingFixedFit :: 8192
TableFlags_SizingFixedSame :: 16384
TableFlags_SizingStretchProp :: 24576
TableFlags_SizingStretchSame :: 32768
TableFlags_NoHostExtendX :: 65536
TableFlags_NoHostExtendY :: 131072
TableFlags_NoKeepColumnsVisible :: 262144
TableFlags_PreciseWidths :: 524288
TableFlags_NoClip :: 1048576
TableFlags_PadOuterX :: 2097152
TableFlags_NoPadOuterX :: 4194304
TableFlags_NoPadInnerX :: 8388608
TableFlags_ScrollX :: 16777216
TableFlags_ScrollY :: 33554432
TableFlags_SortMulti :: 67108864
TableFlags_SortTristate :: 134217728
TableFlags_HighlightHoveredColumn :: 268435456
TableFlags_SizingMask_ :: 57344
TableColumnFlags_None :: 0
TableColumnFlags_Disabled :: 1
TableColumnFlags_DefaultHide :: 2
TableColumnFlags_DefaultSort :: 4
TableColumnFlags_WidthStretch :: 8
TableColumnFlags_WidthFixed :: 16
TableColumnFlags_NoResize :: 32
TableColumnFlags_NoReorder :: 64
TableColumnFlags_NoHide :: 128
TableColumnFlags_NoClip :: 256
TableColumnFlags_NoSort :: 512
TableColumnFlags_NoSortAscending :: 1024
TableColumnFlags_NoSortDescending :: 2048
TableColumnFlags_NoHeaderLabel :: 4096
TableColumnFlags_NoHeaderWidth :: 8192
TableColumnFlags_PreferSortAscending :: 16384
TableColumnFlags_PreferSortDescending :: 32768
TableColumnFlags_IndentEnable :: 65536
TableColumnFlags_IndentDisable :: 131072
TableColumnFlags_AngledHeader :: 262144
TableColumnFlags_IsEnabled :: 16777216
TableColumnFlags_IsVisible :: 33554432
TableColumnFlags_IsSorted :: 67108864
TableColumnFlags_IsHovered :: 134217728
TableColumnFlags_WidthMask_ :: 24
TableColumnFlags_IndentMask_ :: 196608
TableColumnFlags_StatusMask_ :: 251658240
TableColumnFlags_NoDirectResize_ :: 1073741824
TableRowFlags_None :: 0
TableRowFlags_Headers :: 1
TableBgTarget_None :: 0
TableBgTarget_RowBg0 :: 1
TableBgTarget_RowBg1 :: 2
TableBgTarget_CellBg :: 3
ListClipperFlags_None :: 0
ListClipperFlags_NoSetTableRowCounters :: 1
MultiSelectFlags_None :: 0
MultiSelectFlags_SingleSelect :: 1
MultiSelectFlags_NoSelectAll :: 2
MultiSelectFlags_NoRangeSelect :: 4
MultiSelectFlags_NoAutoSelect :: 8
MultiSelectFlags_NoAutoClear :: 16
MultiSelectFlags_NoAutoClearOnReselect :: 32
MultiSelectFlags_BoxSelect1d :: 64
MultiSelectFlags_BoxSelect2d :: 128
MultiSelectFlags_BoxSelectNoScroll :: 256
MultiSelectFlags_ClearOnEscape :: 512
MultiSelectFlags_ClearOnClickVoid :: 1024
MultiSelectFlags_ScopeWindow :: 2048
MultiSelectFlags_ScopeRect :: 4096
MultiSelectFlags_SelectOnAuto :: 8192
MultiSelectFlags_SelectOnClickAlways :: 16384
MultiSelectFlags_SelectOnClickRelease :: 32768
MultiSelectFlags_NavWrapX :: 65536
MultiSelectFlags_NoSelectOnRightClick :: 131072
MultiSelectFlags_SelectOnMask_ :: 57344
MultiSelectFlags_CheckboxMode_ :: 1048576
MultiSelectFlags_SelectOnClick :: 8192
SelectionRequestType_None :: 0
SelectionRequestType_SetAll :: 1
SelectionRequestType_SetRange :: 2
DrawFlags_None :: 0
DrawFlags_RoundTopLeft :: 16
DrawFlags_RoundTopRight :: 32
DrawFlags_RoundBottomLeft :: 64
DrawFlags_RoundBottomRight :: 128
DrawFlags_RoundNone :: 256
DrawFlags_RoundAll :: 240
DrawFlags_RoundTop :: 48
DrawFlags_RoundBottom :: 192
DrawFlags_RoundLeft :: 80
DrawFlags_RoundRight :: 160
DrawFlags_Closed :: 512
DrawFlags_JoinMiter :: 1024
DrawFlags_CapSquare :: 2048
DrawFlags_AAFill :: 4096
DrawFlags_AALines :: 8192
DrawFlags_AALineEnds :: 16384
DrawFlags_StrokeInside :: 131072
DrawFlags_StrokeCenter :: 262144
DrawFlags_StrokeCenterBiased :: 393216
DrawFlags_StrokeOutside :: 524288
DrawFlags_StrokeLegacy :: 917504
DrawFlags_TextNoPixelSnap :: 1048576
DrawFlags_UseTexForRoundCorners :: 2097152
DrawFlags_UseVtxOffset :: 4194304
DrawFlags_AllowTexForRoundCorners_ :: 8388608
DrawFlags_RoundMask_ :: 496
DrawFlags_AllowInPushScope_ :: 8286704
DrawFlags_AllowInFrameScope_ :: 16675312
DrawFlags_StrokeMask_ :: 917504
DrawFlags_InvalidMask_ :: -2147483633
DrawFlags_RoundCornersTopLeft :: 16
DrawFlags_RoundCornersTopRight :: 32
DrawFlags_RoundCornersBottomLeft :: 64
DrawFlags_RoundCornersBottomRight :: 128
DrawFlags_RoundCornersNone :: 256
DrawFlags_RoundCornersAll :: 240
DrawFlags_RoundCornersTop :: 48
DrawFlags_RoundCornersBottom :: 192
DrawFlags_RoundCornersLeft :: 80
DrawFlags_RoundCornersRight :: 160
TextureFormat_RGBA32 :: 0
TextureFormat_Alpha8 :: 1
TextureStatus_OK :: 0
TextureStatus_Destroyed :: 1
TextureStatus_WantCreate :: 2
TextureStatus_WantUpdates :: 3
TextureStatus_WantDestroy :: 4
FontAtlasFlags_None :: 0
FontAtlasFlags_NoPowerOfTwoHeight :: 1
FontAtlasFlags_NoMouseCursors :: 2
FontAtlasFlags_NoBakedLines :: 4
FontAtlasFlags_NoBakedRoundCorners :: 8
FontFlags_None :: 0
FontFlags_NoLoadError :: 2
FontFlags_NoLoadGlyphs :: 4
FontFlags_LockBakedSizes :: 8
FontFlags_ImplicitRefSize :: 16
ViewportFlags_None :: 0
ViewportFlags_IsPlatformWindow :: 1
ViewportFlags_IsPlatformMonitor :: 2
ViewportFlags_OwnedByApp :: 4
DrawListFlags_None :: 0
DrawListFlags_AntiAliasedFill :: 4096
DrawListFlags_AntiAliasedLines :: 8192
DrawListFlags_AntiAliasedLinesUseTex :: 8192
DrawListFlags_AllowVtxOffset :: 4194304
DrawListFlags_TextNoPixelSnap :: 1048576
ImplSDL3_GamepadMode_AutoFirst :: 0
ImplSDL3_GamepadMode_AutoAll :: 1
ImplSDL3_GamepadMode_Manual :: 2
ImplSDL3_MouseCaptureMode_Enabled :: 0
ImplSDL3_MouseCaptureMode_EnabledAfterDrag :: 1
ImplSDL3_MouseCaptureMode_Disabled :: 2

SelectionRequestType :: i32
TextureFormat :: i32
TextureStatus :: i32
ImplSDL3_GamepadMode :: i32
ImplSDL3_MouseCaptureMode :: i32
InputTextCallback :: proc "c" (data: ^InputTextCallbackData) -> i32
SizeCallback :: proc "c" (data: ^SizeCallbackData)
MemAllocFunc :: proc "c" (sz: uint, user_data: rawptr) -> rawptr
MemFreeFunc :: proc "c" (ptr: rawptr, user_data: rawptr)
DrawCallback :: proc "c" (parent_list: ^DrawList, cmd: ^DrawCmd)

TextFilterItem :: struct {}

DrawListSharedData :: struct {}

FontAtlasBuilder :: struct {}

FontLoader :: struct {}

Context :: struct {}

Vec2 :: [2]f32

Vec4 :: [4]f32

TextureRef :: struct {
	_tex_data: ^TextureData,
	_tex_id: TextureID,
}

TableSortSpecs :: struct {
	specs: ^TableColumnSortSpecs,
	specs_count: i32,
	specs_dirty: bool,
}

TableColumnSortSpecs :: struct {
	column_user_id: ID,
	column_index: S16,
	sort_order: S16,
	sort_direction: SortDirection,
}

Vector_ImGuiTextFilterItem :: struct {
	size: i32,
	capacity: i32,
	data: ^TextFilterItem,
}

Vector_char :: struct {
	size: i32,
	capacity: i32,
	data: cstring,
}

Vector_ImGuiStoragePair :: struct {
	size: i32,
	capacity: i32,
	data: ^StoragePair,
}

Vector_ImGuiSelectionRequest :: struct {
	size: i32,
	capacity: i32,
	data: ^SelectionRequest,
}

Vector_ImDrawChannel :: struct {
	size: i32,
	capacity: i32,
	data: ^DrawChannel,
}

Vector_ImDrawCmd :: struct {
	size: i32,
	capacity: i32,
	data: ^DrawCmd,
}

Vector_ImDrawIdx :: struct {
	size: i32,
	capacity: i32,
	data: ^DrawIdx,
}

Vector_ImDrawVert :: struct {
	size: i32,
	capacity: i32,
	data: ^DrawVert,
}

Vector_ImVec2 :: struct {
	size: i32,
	capacity: i32,
	data: ^[2]f32,
}

Vector_ImVec4 :: struct {
	size: i32,
	capacity: i32,
	data: ^[4]f32,
}

Vector_ImTextureRef :: struct {
	size: i32,
	capacity: i32,
	data: ^TextureRef,
}

Vector_ImU8 :: struct {
	size: i32,
	capacity: i32,
	data: ^U8,
}

Vector_ImDrawListPtr :: struct {
	size: i32,
	capacity: i32,
	data: ^^DrawList,
}

Vector_ImTextureRect :: struct {
	size: i32,
	capacity: i32,
	data: ^TextureRect,
}

Vector_ImU32 :: struct {
	size: i32,
	capacity: i32,
	data: ^U32,
}

Vector_ImWchar :: struct {
	size: i32,
	capacity: i32,
	data: ^Wchar,
}

Vector_ImFontPtr :: struct {
	size: i32,
	capacity: i32,
	data: ^^Font,
}

Vector_ImFontConfig :: struct {
	size: i32,
	capacity: i32,
	data: ^FontConfig,
}

Vector_ImDrawListSharedDataPtr :: struct {
	size: i32,
	capacity: i32,
	data: ^^DrawListSharedData,
}

Vector_float :: struct {
	size: i32,
	capacity: i32,
	data: ^f32,
}

Vector_ImU16 :: struct {
	size: i32,
	capacity: i32,
	data: ^U16,
}

Vector_ImFontGlyph :: struct {
	size: i32,
	capacity: i32,
	data: ^FontGlyph,
}

Vector_ImFontConfigPtr :: struct {
	size: i32,
	capacity: i32,
	data: ^^FontConfig,
}

Vector_ImTextureDataPtr :: struct {
	size: i32,
	capacity: i32,
	data: ^^TextureData,
}

Style :: struct {
	font_size_base: f32,
	font_scale_main: f32,
	font_scale_dpi: f32,
	alpha: f32,
	disabled_alpha: f32,
	window_padding: [2]f32,
	window_rounding: f32,
	window_border_size: f32,
	window_border_hover_padding: f32,
	window_min_size: [2]f32,
	window_title_align: [2]f32,
	window_menu_button_position: Dir,
	child_rounding: f32,
	child_border_size: f32,
	popup_rounding: f32,
	popup_border_size: f32,
	frame_padding: [2]f32,
	frame_rounding: f32,
	frame_border_size: f32,
	item_spacing: [2]f32,
	item_inner_spacing: [2]f32,
	cell_padding: [2]f32,
	touch_extra_padding: [2]f32,
	indent_spacing: f32,
	columns_min_spacing: f32,
	scrollbar_size: f32,
	scrollbar_rounding: f32,
	scrollbar_padding: f32,
	grab_min_size: f32,
	grab_rounding: f32,
	log_slider_deadzone: f32,
	image_rounding: f32,
	image_border_size: f32,
	tab_rounding: f32,
	tab_border_size: f32,
	tab_min_width_base: f32,
	tab_min_width_shrink: f32,
	tab_close_button_min_width_selected: f32,
	tab_close_button_min_width_unselected: f32,
	tab_bar_border_size: f32,
	tab_bar_overline_size: f32,
	table_angled_headers_angle: f32,
	table_angled_headers_text_align: [2]f32,
	tree_lines_flags: TreeNodeFlags,
	tree_lines_size: f32,
	tree_lines_rounding: f32,
	menu_item_rounding: f32,
	selectable_rounding: f32,
	drag_drop_target_rounding: f32,
	drag_drop_target_border_size: f32,
	drag_drop_target_padding: f32,
	color_marker_size: f32,
	color_button_position: Dir,
	button_text_align: [2]f32,
	selectable_text_align: [2]f32,
	input_text_cursor_size: f32,
	separator_size: f32,
	separator_text_border_size: f32,
	separator_text_align: [2]f32,
	separator_text_padding: [2]f32,
	display_window_padding: [2]f32,
	display_safe_area_padding: [2]f32,
	mouse_cursor_scale: f32,
	anti_aliased_lines: bool,
	anti_aliased_line_ends: bool,
	anti_aliased_fill: bool,
	curve_tessellation_max_error: f32,
	circle_tessellation_max_error: f32,
	colors: [61][4]f32,
	hover_stationary_delay: f32,
	hover_delay_short: f32,
	hover_delay_normal: f32,
	hover_flags_for_tooltip_mouse: HoveredFlags,
	hover_flags_for_tooltip_nav: HoveredFlags,
	_main_scale: f32,
	_next_frame_font_size_base: f32,
	anti_aliased_lines_use_tex: bool,
	curve_tessellation_tol: f32,
}

KeyData :: struct {
	down: bool,
	down_duration: f32,
	down_duration_prev: f32,
	analog_value: f32,
}

IO :: struct {
	config_flags: ConfigFlags,
	backend_flags: BackendFlags,
	display_size: [2]f32,
	display_framebuffer_scale: [2]f32,
	delta_time: f32,
	ini_saving_rate: f32,
	ini_filename: cstring,
	log_filename: cstring,
	user_data: rawptr,
	fonts: ^FontAtlas,
	font_default: ^Font,
	font_allow_user_scaling: bool,
	config_nav_swap_gamepad_buttons: bool,
	config_nav_move_set_mouse_pos: bool,
	config_nav_capture_keyboard: bool,
	config_nav_escape_clear_focus_item: bool,
	config_nav_escape_clear_focus_window: bool,
	config_nav_cursor_visible_auto: bool,
	config_nav_cursor_visible_always: bool,
	config_mac_osx_behaviors: bool,
	config_input_trickle_event_queue: bool,
	config_input_text_cursor_blink: bool,
	config_input_text_enter_keep_active: bool,
	config_color_edit_flags: ColorEditFlags,
	config_drag_click_to_input_text: bool,
	config_windows_resize_from_edges: bool,
	config_windows_move_from_title_bar_only: bool,
	config_windows_copy_contents_with_ctrl_c: bool,
	config_scrollbar_scroll_by_page: bool,
	config_ini_settings_save_last_used_date: bool,
	config_ini_settings_auto_discard_months: i32,
	config_debug_ini_settings: bool,
	mouse_draw_cursor: bool,
	config_memory_compact_timer: f32,
	mouse_double_click_time: f32,
	mouse_double_click_max_dist: f32,
	mouse_single_click_delay: f32,
	mouse_drag_threshold: f32,
	key_repeat_delay: f32,
	key_repeat_rate: f32,
	config_error_recovery: bool,
	config_error_recovery_enable_assert: bool,
	config_error_recovery_enable_debug_log: bool,
	config_error_recovery_enable_tooltip: bool,
	config_debug_is_debugger_present: bool,
	config_debug_highlight_id_conflicts: bool,
	config_debug_highlight_id_conflicts_show_item_picker: bool,
	config_debug_begin_return_value_once: bool,
	config_debug_begin_return_value_loop: bool,
	config_debug_ignore_focus_loss: bool,
	config_debug_draw_list_defaults_to_stroke_legacy: bool,
	backend_platform_name: cstring,
	backend_renderer_name: cstring,
	backend_platform_user_data: rawptr,
	backend_renderer_user_data: rawptr,
	backend_language_user_data: rawptr,
	want_capture_mouse: bool,
	want_capture_keyboard: bool,
	want_text_input: bool,
	want_set_mouse_pos: bool,
	want_save_ini_settings: bool,
	nav_active: bool,
	nav_visible: bool,
	framerate: f32,
	metrics_render_vertices: i32,
	metrics_render_indices: i32,
	metrics_render_windows: i32,
	metrics_active_windows: i32,
	mouse_delta: [2]f32,
	ctx: ^Context,
	mouse_pos: [2]f32,
	mouse_down: [5]bool,
	mouse_wheel: f32,
	mouse_wheel_h: f32,
	mouse_source: MouseSource,
	key_ctrl: bool,
	key_shift: bool,
	key_alt: bool,
	key_super: bool,
	key_mods: KeyChord,
	keys_data: [155]KeyData,
	want_capture_mouse_unless_popup_close: bool,
	mouse_pos_prev: [2]f32,
	mouse_clicked_pos: [5][2]f32,
	mouse_clicked_time: [5]f64,
	mouse_clicked: [5]bool,
	mouse_double_clicked: [5]bool,
	mouse_clicked_count: [5]U16,
	mouse_clicked_last_count: [5]U16,
	mouse_released: [5]bool,
	mouse_released_time: [5]f64,
	mouse_down_owned: [5]bool,
	mouse_down_owned_unless_popup_close: [5]bool,
	mouse_wheel_request_axis_swap: bool,
	mouse_ctrl_left_as_right_click: bool,
	mouse_down_duration: [5]f32,
	mouse_down_duration_prev: [5]f32,
	mouse_drag_max_distance_sqr: [5]f32,
	pen_pressure: f32,
	app_focus_lost: bool,
	app_accepting_events: bool,
	input_queue_surrogate: Wchar16,
	input_queue_characters: Vector_ImWchar,
	font_global_scale: f32,
	get_clipboard_text_fn: proc "c" (user_data: rawptr) -> cstring,
	set_clipboard_text_fn: proc "c" (user_data: rawptr, text: cstring),
	clipboard_user_data: rawptr,
}

InputTextCallbackData :: struct {
	ctx: ^Context,
	event_flag: InputTextFlags,
	flags: InputTextFlags,
	user_data: rawptr,
	id: ID,
	event_key: Key,
	event_char: Wchar,
	event_activated: bool,
	buf_dirty: bool,
	buf: cstring,
	buf_text_len: i32,
	buf_size: i32,
	cursor_pos: i32,
	selection_start: i32,
	selection_end: i32,
}

SizeCallbackData :: struct {
	user_data: rawptr,
	pos: [2]f32,
	current_size: [2]f32,
	desired_size: [2]f32,
}

Payload :: struct {
	data: rawptr,
	data_size: i32,
	source_id: ID,
	source_parent_id: ID,
	data_frame_count: i32,
	data_type: [33]u8,
	preview: bool,
	delivery: bool,
}

TextFilter :: struct {
	input_buf: [256]u8,
	_count_exclude: i32,
	_items: Vector_ImGuiTextFilterItem,
}

TextBuffer :: struct {
	buf: Vector_char,
}

StoragePair :: struct {
	key: ID,
	__anonymous_type0: __anonymous_type0,
}

__anonymous_type0 :: struct #raw_union {
	val_i: i32,
	val_f: f32,
	val_p: rawptr,
}

Storage :: struct {
	data: Vector_ImGuiStoragePair,
}

SmallStack__ImDrawFlags_3_ImU16 :: struct {
	local_data: [3]DrawFlags,
	size: U16,
}

ListClipper :: struct {
	display_start: i32,
	display_end: i32,
	user_index: i32,
	items_count: i32,
	items_height: f32,
	flags: ListClipperFlags,
	start_pos_y: f64,
	start_seek_offset_y: f64,
	ctx: ^Context,
	temp_data: rawptr,
}

Color :: struct {
	value: [4]f32,
}

MultiSelectIO :: struct {
	requests: Vector_ImGuiSelectionRequest,
	range_src_item: SelectionUserData,
	nav_id_item: SelectionUserData,
	nav_id_selected: bool,
	range_src_reset: bool,
	items_count: i32,
}

SelectionRequest :: struct {
	type_: SelectionRequestType,
	selected: bool,
	range_direction: S8,
	range_first_item: SelectionUserData,
	range_last_item: SelectionUserData,
}

SelectionBasicStorage :: struct {
	size: i32,
	preserve_order: bool,
	user_data: rawptr,
	adapter_index_to_storage_id: proc "c" (self: ^SelectionBasicStorage, idx: i32) -> ID,
	_selection_order: i32,
	_storage: Storage,
}

SelectionExternalStorage :: struct {
	user_data: rawptr,
	adapter_set_item_selected: proc "c" (self: ^SelectionExternalStorage, idx: i32, selected: bool),
}

DrawCmd :: struct {
	clip_rect: [4]f32,
	tex_ref: TextureRef,
	vtx_offset: u32,
	idx_offset: u32,
	elem_count: u32,
	user_callback: DrawCallback,
	user_callback_data: rawptr,
	user_callback_data_size: i32,
	user_callback_data_offset: i32,
}

DrawVert :: struct {
	pos: [2]f32,
	uv: [2]f32,
	col: U32,
}

DrawCmdHeader :: struct {
	clip_rect: [4]f32,
	tex_ref: TextureRef,
	vtx_offset: u32,
}

DrawChannel :: struct {
	_cmd_buffer: Vector_ImDrawCmd,
	_idx_buffer: Vector_ImDrawIdx,
}

DrawListSplitter :: struct {
	_current: i32,
	_count: i32,
	_channels: Vector_ImDrawChannel,
}

DrawList :: struct {
	cmd_buffer: Vector_ImDrawCmd,
	idx_buffer: Vector_ImDrawIdx,
	vtx_buffer: Vector_ImDrawVert,
	flags: DrawFlags,
	_vtx_current_idx: u32,
	_data: ^DrawListSharedData,
	_vtx_write_ptr: ^DrawVert,
	_idx_write_ptr: ^DrawIdx,
	_path: Vector_ImVec2,
	_cmd_header: DrawCmdHeader,
	_splitter: DrawListSplitter,
	_clip_rect_stack: Vector_ImVec4,
	_texture_stack: Vector_ImTextureRef,
	_callbacks_data_buf: Vector_ImU8,
	_draw_flags_stack: SmallStack__ImDrawFlags_3_ImU16,
	_fringe_scale: f32,
	_inv_fringe_scale: f32,
	_fringe_scale_is_integer: bool,
	_owner_name: cstring,
}

DrawData :: struct {
	valid: bool,
	frame_count: i32,
	total_idx_count: i32,
	total_vtx_count: i32,
	cmd_lists: Vector_ImDrawListPtr,
	display_pos: [2]f32,
	display_size: [2]f32,
	framebuffer_scale: [2]f32,
	owner_viewport: ^Viewport,
	textures: ^Vector_ImTextureDataPtr,
	cmd_lists_count: i32,
}

TextureRect :: struct {
	x: u16,
	y: u16,
	w: u16,
	h: u16,
}

TextureData :: struct {
	unique_id: i32,
	status: TextureStatus,
	backend_user_data: rawptr,
	queue_user_data: rawptr,
	tex_id: TextureID,
	format: TextureFormat,
	width: i32,
	height: i32,
	bytes_per_pixel: i32,
	pixels: ^u8,
	used_rect: TextureRect,
	update_rect: TextureRect,
	updates: Vector_ImTextureRect,
	unused_frames: i32,
	ref_count: u16,
	use_colors: bool,
	want_destroy_next_frame: bool,
}

FontConfig :: struct {
	name: [40]u8,
	font_data: rawptr,
	font_data_size: i32,
	font_data_owned_by_atlas: bool,
	merge_mode: bool,
	pixel_snap_h: bool,
	oversample_h: S8,
	oversample_v: S8,
	ellipsis_char: Wchar,
	size_pixels: f32,
	glyph_ranges: ^Wchar,
	glyph_exclude_ranges: ^Wchar,
	glyph_offset: [2]f32,
	glyph_min_advance_x: f32,
	glyph_max_advance_x: f32,
	glyph_extra_advance_x: f32,
	font_no: U32,
	font_loader_flags: u32,
	rasterizer_multiply: f32,
	rasterizer_density: f32,
	extra_size_scale: f32,
	flags: FontFlags,
	dst_font: ^Font,
	font_loader: ^FontLoader,
	font_loader_data: rawptr,
	pixel_snap_v: bool,
}

FontGlyph :: struct {
	colored: u32,
	visible: u32,
	source_idx: u32,
	codepoint: u32,
	advance_x: f32,
	x0: f32,
	y0: f32,
	x1: f32,
	y1: f32,
	u0: f32,
	v0: f32,
	u1: f32,
	v1: f32,
	pack_id: i32,
}

FontGlyphRangesBuilder :: struct {
	used_chars: Vector_ImU32,
}

FontAtlasRect :: struct {
	x: u16,
	y: u16,
	w: u16,
	h: u16,
	uv0: [2]f32,
	uv1: [2]f32,
}

FontAtlas :: struct {
	flags: FontAtlasFlags,
	tex_desired_format: TextureFormat,
	tex_glyph_padding: i32,
	tex_min_width: i32,
	tex_min_height: i32,
	tex_max_width: i32,
	tex_max_height: i32,
	user_data: rawptr,
	tex_ref: TextureRef,
	__anonymous_type1: __anonymous_type1,
	tex_data: ^TextureData,
	tex_list: Vector_ImTextureDataPtr,
	locked: bool,
	renderer_has_textures: bool,
	tex_is_built: bool,
	tex_pixels_use_colors: bool,
	tex_uv_scale: [2]f32,
	tex_uv_white_pixel: [2]f32,
	fonts: Vector_ImFontPtr,
	sources: Vector_ImFontConfig,
	tex_next_unique_id: i32,
	font_next_unique_id: i32,
	draw_list_shared_datas: Vector_ImDrawListSharedDataPtr,
	builder: ^FontAtlasBuilder,
	font_loader: ^FontLoader,
	font_loader_name: cstring,
	font_loader_data: rawptr,
	font_loader_flags: u32,
	ref_count: i32,
	owner_context: ^Context,
	temp_rect: FontAtlasRect,
}

__anonymous_type1 :: struct #raw_union {
	tex_ref: TextureRef,
	tex_id: TextureRef,
}

FontBaked :: struct {
	index_advance_x: Vector_float,
	fallback_advance_x: f32,
	size: f32,
	rasterizer_density: f32,
	index_lookup: Vector_ImU16,
	glyphs: Vector_ImFontGlyph,
	fallback_glyph_index: i32,
	ascent: f32,
	descent: f32,
	metrics_total_surface: u32,
	want_destroy: u32,
	load_no_fallback: u32,
	load_no_render_on_layout: u32,
	last_used_frame: i32,
	baked_id: ID,
	owner_font: ^Font,
	font_loader_datas: rawptr,
}

Font :: struct {
	last_baked: ^FontBaked,
	owner_atlas: ^FontAtlas,
	flags: FontFlags,
	current_rasterizer_density: f32,
	font_id: ID,
	legacy_size: f32,
	sources: Vector_ImFontConfigPtr,
	ellipsis_char: Wchar,
	fallback_char: Wchar,
	used8k_pages_map: [1]U8,
	ellipsis_auto_bake: bool,
	remap_pairs: Storage,
	scale: f32,
}

Viewport :: struct {
	id: ID,
	flags: ViewportFlags,
	pos: [2]f32,
	size: [2]f32,
	framebuffer_scale: [2]f32,
	work_pos: [2]f32,
	work_size: [2]f32,
	platform_handle: rawptr,
	platform_handle_raw: rawptr,
}

PlatformIO :: struct {
	platform_get_clipboard_text_fn: proc "c" (ctx: ^Context) -> cstring,
	platform_set_clipboard_text_fn: proc "c" (ctx: ^Context, text: cstring),
	platform_clipboard_user_data: rawptr,
	platform_open_in_shell_fn: proc "c" (ctx: ^Context, path: cstring) -> bool,
	platform_open_in_shell_user_data: rawptr,
	platform_set_ime_data_fn: proc "c" (ctx: ^Context, viewport: ^Viewport, data: ^PlatformImeData),
	platform_ime_user_data: rawptr,
	platform_locale_decimal_point: Wchar,
	platform_session_date: i32,
	renderer_texture_max_width: i32,
	renderer_texture_max_height: i32,
	renderer_render_state: rawptr,
	draw_callback_reset_render_state: DrawCallback,
	draw_callback_set_sampler_linear: DrawCallback,
	draw_callback_set_sampler_nearest: DrawCallback,
	draw_callback_set_sampler_from_tex: DrawCallback,
	textures: Vector_ImTextureDataPtr,
}

PlatformImeData :: struct {
	want_visible: bool,
	want_text_input: bool,
	input_pos: [2]f32,
	input_line_height: f32,
	viewport_id: ID,
}

SDL_Window :: struct {}

SDL_Renderer :: struct {}

SDL_Gamepad :: struct {}

ImplSDLGPU3_InitInfo :: struct {
	device: ^sdl.GPUDevice,
	color_target_format: sdl.GPUTextureFormat,
	msaa_samples: sdl.GPUSampleCount,
	swapchain_composition: sdl.GPUSwapchainComposition,
	present_mode: sdl.GPUPresentMode,
}

ImplSDLGPU3_RenderState :: struct {
	device: ^sdl.GPUDevice,
}

@(default_calling_convention = "c")
foreign lib {
	@(link_name = "ImGui_CreateContext") create_context :: proc(shared_font_atlas: ^FontAtlas = nil) -> ^Context ---
	@(link_name = "ImGui_DestroyContext") destroy_context :: proc(ctx: ^Context = nil) ---
	@(link_name = "ImGui_GetIO") get_io :: proc() -> ^IO ---
	@(link_name = "ImGui_GetStyle") get_style :: proc() -> ^Style ---
	@(link_name = "ImGui_NewFrame") new_frame :: proc() ---
	@(link_name = "ImGui_EndFrame") end_frame :: proc() ---
	@(link_name = "ImGui_Render") render :: proc() ---
	@(link_name = "ImGui_GetDrawData") get_draw_data :: proc() -> ^DrawData ---
	@(link_name = "ImGui_StyleColorsDark") style_colors_dark :: proc(dst: ^Style = nil) ---
	@(link_name = "ImGui_StyleColorsLight") style_colors_light :: proc(dst: ^Style = nil) ---
	@(link_name = "ImGui_Begin") begin :: proc(name: cstring, p_open: ^bool = nil, flags: WindowFlags = 0) -> bool ---
	@(link_name = "ImGui_End") end :: proc() ---
	@(link_name = "ImGui_BeginChild") begin_child :: proc(str_id: cstring, size: [2]f32 = {0, 0}, child_flags: ChildFlags = 0, window_flags: WindowFlags = 0) -> bool ---
	@(link_name = "ImGui_EndChild") end_child :: proc() ---
	@(link_name = "ImGui_IsWindowFocused") is_window_focused :: proc(flags: FocusedFlags = 0) -> bool ---
	@(link_name = "ImGui_GetWindowDrawList") get_window_draw_list :: proc() -> ^DrawList ---
	@(link_name = "ImGui_SetNextWindowPos") set_next_window_pos :: proc(pos: [2]f32, cond: Cond = 0) ---
	@(link_name = "ImGui_SetNextWindowSize") set_next_window_size :: proc(size: [2]f32, cond: Cond = 0) ---
	@(link_name = "ImGui_SetNextWindowCollapsed") set_next_window_collapsed :: proc(collapsed: bool, cond: Cond = 0) ---
	@(link_name = "ImGui_SetNextWindowBgAlpha") set_next_window_bg_alpha :: proc(alpha: f32) ---
	@(link_name = "ImGui_PushStyleColor") push_style_color :: proc(idx: Col, col: U32) ---
	@(link_name = "ImGui_PopStyleColor") pop_style_color :: proc() ---
	@(link_name = "ImGui_PushStyleVar") push_style_var :: proc(idx: StyleVar, val: f32) ---
	@(link_name = "ImGui_PushStyleVarImVec2") push_style_var_im_vec2 :: proc(idx: StyleVar, val: [2]f32) ---
	@(link_name = "ImGui_PopStyleVar") pop_style_var :: proc() ---
	@(link_name = "ImGui_PushItemWidth") push_item_width :: proc(item_width: f32) ---
	@(link_name = "ImGui_PopItemWidth") pop_item_width :: proc() ---
	@(link_name = "ImGui_SetNextItemWidth") set_next_item_width :: proc(item_width: f32) ---
	@(link_name = "ImGui_GetColorU32") get_color_u32 :: proc(idx: Col) -> U32 ---
	@(link_name = "ImGui_GetColorU32ImU32") get_color_u32_im_u32 :: proc(col: U32) -> U32 ---
	@(link_name = "ImGui_GetCursorScreenPos") get_cursor_screen_pos :: proc() -> [2]f32 ---
	@(link_name = "ImGui_SetCursorScreenPos") set_cursor_screen_pos :: proc(pos: [2]f32) ---
	@(link_name = "ImGui_GetContentRegionAvail") get_content_region_avail :: proc() -> [2]f32 ---
	@(link_name = "ImGui_Separator") separator :: proc() ---
	@(link_name = "ImGui_SameLine") same_line :: proc() ---
	@(link_name = "ImGui_NewLine") new_line :: proc() ---
	@(link_name = "ImGui_Spacing") spacing :: proc() ---
	@(link_name = "ImGui_Dummy") dummy :: proc(size: [2]f32) ---
	@(link_name = "ImGui_BeginGroup") begin_group :: proc() ---
	@(link_name = "ImGui_EndGroup") end_group :: proc() ---
	@(link_name = "ImGui_GetTextLineHeight") get_text_line_height :: proc() -> f32 ---
	@(link_name = "ImGui_GetFrameHeight") get_frame_height :: proc() -> f32 ---
	@(link_name = "ImGui_PushID") push_id :: proc(str_id: cstring) ---
	@(link_name = "ImGui_PushIDInt") push_id_int :: proc(int_id: i32) ---
	@(link_name = "ImGui_PopID") pop_id :: proc() ---
	@(link_name = "ImGui_GetID") get_id :: proc(str_id: cstring) -> ID ---
	@(link_name = "ImGui_TextUnformatted") text_unformatted :: proc(text: cstring) ---
	@(link_name = "ImGui_Text") text :: proc(fmt: cstring, #c_vararg args: ..any) ---
	@(link_name = "ImGui_TextWrapped") text_wrapped :: proc(fmt: cstring, #c_vararg args: ..any) ---
	@(link_name = "ImGui_Button") button :: proc(label: cstring) -> bool ---
	@(link_name = "ImGui_SmallButton") small_button :: proc(label: cstring) -> bool ---
	@(link_name = "ImGui_InvisibleButton") invisible_button :: proc(str_id: cstring, size: [2]f32, flags: ButtonFlags = 0) -> bool ---
	@(link_name = "ImGui_Checkbox") checkbox :: proc(label: cstring, v: ^bool) -> bool ---
	@(link_name = "ImGui_RadioButton") radio_button :: proc(label: cstring, active: bool) -> bool ---
	@(link_name = "ImGui_ProgressBar") progress_bar :: proc(fraction: f32, size_arg: [2]f32, overlay: cstring = nil) ---
	@(link_name = "ImGui_BeginCombo") begin_combo :: proc(label: cstring, preview_value: cstring, flags: ComboFlags = 0) -> bool ---
	@(link_name = "ImGui_EndCombo") end_combo :: proc() ---
	@(link_name = "ImGui_DragFloat") drag_float :: proc(label: cstring, v: ^f32) -> bool ---
	@(link_name = "ImGui_DragFloat2") drag_float2 :: proc(label: cstring, v: ^[2][2]f32) -> bool ---
	@(link_name = "ImGui_DragFloatRange2Ex") drag_float_range2_ex :: proc(label: cstring, v_current_min: ^f32, v_current_max: ^f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring, format_max: cstring = nil, flags: SliderFlags = 0) -> bool ---
	@(link_name = "ImGui_SliderFloat") slider_float :: proc(label: cstring, v: ^f32, v_min: f32, v_max: f32) -> bool ---
	@(link_name = "ImGui_SliderFloatEx") slider_float_ex :: proc(label: cstring, v: ^f32, v_min: f32, v_max: f32, format: cstring, flags: SliderFlags = 0) -> bool ---
	@(link_name = "ImGui_SliderInt") slider_int :: proc(label: cstring, v: ^i32, v_min: i32, v_max: i32) -> bool ---
	@(link_name = "ImGui_SliderIntEx") slider_int_ex :: proc(label: cstring, v: ^i32, v_min: i32, v_max: i32, format: cstring, flags: SliderFlags = 0) -> bool ---
	@(link_name = "ImGui_InputText") input_text :: proc(label: cstring, buf: cstring, buf_size: uint, flags: InputTextFlags = 0) -> bool ---
	@(link_name = "ImGui_InputTextMultiline") input_text_multiline :: proc(label: cstring, buf: cstring, buf_size: uint) -> bool ---
	@(link_name = "ImGui_InputTextWithHint") input_text_with_hint :: proc(label: cstring, hint: cstring, buf: cstring, buf_size: uint, flags: InputTextFlags = 0) -> bool ---
	@(link_name = "ImGui_InputFloat") input_float :: proc(label: cstring, v: ^f32) -> bool ---
	@(link_name = "ImGui_InputInt") input_int :: proc(label: cstring, v: ^i32) -> bool ---
	@(link_name = "ImGui_InputDouble") input_double :: proc(label: cstring, v: ^f64) -> bool ---
	@(link_name = "ImGui_ColorEdit4") color_edit4 :: proc(label: cstring, col: ^[4][4]f32, flags: ColorEditFlags = 0) -> bool ---
	@(link_name = "ImGui_ColorPicker4") color_picker4 :: proc(label: cstring, col: ^[4][4]f32, flags: ColorEditFlags = 0, ref_col: ^f32 = nil) -> bool ---
	@(link_name = "ImGui_Selectable") selectable :: proc(label: cstring) -> bool ---
	@(link_name = "ImGui_SelectableBoolPtr") selectable_bool_ptr :: proc(label: cstring, p_selected: ^bool, flags: SelectableFlags = 0) -> bool ---
	@(link_name = "ImGui_BeginListBox") begin_list_box :: proc(label: cstring, size: [2]f32 = {0, 0}) -> bool ---
	@(link_name = "ImGui_EndListBox") end_list_box :: proc() ---
	@(link_name = "ImGui_BeginMenuBar") begin_menu_bar :: proc() -> bool ---
	@(link_name = "ImGui_EndMenuBar") end_menu_bar :: proc() ---
	@(link_name = "ImGui_BeginMainMenuBar") begin_main_menu_bar :: proc() -> bool ---
	@(link_name = "ImGui_EndMainMenuBar") end_main_menu_bar :: proc() ---
	@(link_name = "ImGui_BeginMenu") begin_menu :: proc(label: cstring) -> bool ---
	@(link_name = "ImGui_EndMenu") end_menu :: proc() ---
	@(link_name = "ImGui_MenuItem") menu_item :: proc(label: cstring) -> bool ---
	@(link_name = "ImGui_MenuItemBoolPtr") menu_item_bool_ptr :: proc(label: cstring, shortcut: cstring, p_selected: ^bool, enabled: bool = true) -> bool ---
	@(link_name = "ImGui_BeginTooltip") begin_tooltip :: proc() -> bool ---
	@(link_name = "ImGui_EndTooltip") end_tooltip :: proc() ---
	@(link_name = "ImGui_SetTooltip") set_tooltip :: proc(fmt: cstring, #c_vararg args: ..any) ---
	@(link_name = "ImGui_SetItemTooltip") set_item_tooltip :: proc(fmt: cstring, #c_vararg args: ..any) ---
	@(link_name = "ImGui_BeginTabBar") begin_tab_bar :: proc(str_id: cstring, flags: TabBarFlags = 0) -> bool ---
	@(link_name = "ImGui_EndTabBar") end_tab_bar :: proc() ---
	@(link_name = "ImGui_BeginTabItem") begin_tab_item :: proc(label: cstring, p_open: ^bool = nil, flags: TabItemFlags = 0) -> bool ---
	@(link_name = "ImGui_EndTabItem") end_tab_item :: proc() ---
	@(link_name = "ImGui_BeginDisabled") begin_disabled :: proc(disabled: bool = true) ---
	@(link_name = "ImGui_EndDisabled") end_disabled :: proc() ---
	@(link_name = "ImGui_SetItemDefaultFocus") set_item_default_focus :: proc() ---
	@(link_name = "ImGui_SetKeyboardFocusHere") set_keyboard_focus_here :: proc() ---
	@(link_name = "ImGui_SetKeyboardFocusHereEx") set_keyboard_focus_here_ex :: proc(offset: i32 = 0) ---
	@(link_name = "ImGui_IsItemHovered") is_item_hovered :: proc(flags: HoveredFlags = 0) -> bool ---
	@(link_name = "ImGui_IsItemActive") is_item_active :: proc() -> bool ---
	@(link_name = "ImGui_IsItemFocused") is_item_focused :: proc() -> bool ---
	@(link_name = "ImGui_IsItemClicked") is_item_clicked :: proc() -> bool ---
	@(link_name = "ImGui_IsItemActivated") is_item_activated :: proc() -> bool ---
	@(link_name = "ImGui_IsItemDeactivatedAfterEdit") is_item_deactivated_after_edit :: proc() -> bool ---
	@(link_name = "ImGui_IsAnyItemActive") is_any_item_active :: proc() -> bool ---
	@(link_name = "ImGui_IsAnyItemFocused") is_any_item_focused :: proc() -> bool ---
	@(link_name = "ImGui_GetItemID") get_item_id :: proc() -> ID ---
	@(link_name = "ImGui_GetItemRectMin") get_item_rect_min :: proc() -> [2]f32 ---
	@(link_name = "ImGui_GetItemRectMax") get_item_rect_max :: proc() -> [2]f32 ---
	@(link_name = "ImGui_GetItemRectSize") get_item_rect_size :: proc() -> [2]f32 ---
	@(link_name = "ImGui_CalcTextSize") calc_text_size :: proc(text: cstring) -> [2]f32 ---
	@(link_name = "ImDrawList_AddLine") draw_list_add_line :: proc(self: ^DrawList, p1: [2]f32, p2: [2]f32, col: U32) ---
	@(link_name = "ImDrawList_AddLineEx") draw_list_add_line_ex :: proc(self: ^DrawList, p1: [2]f32, p2: [2]f32, col: U32, thickness: f32 = 1.0, flags: DrawFlags = 0) ---
	@(link_name = "ImDrawList_AddRect") draw_list_add_rect :: proc(self: ^DrawList, p_min: [2]f32, p_max: [2]f32, col: U32) ---
	@(link_name = "ImDrawList_AddRectFilled") draw_list_add_rect_filled :: proc(self: ^DrawList, p_min: [2]f32, p_max: [2]f32, col: U32) ---
	@(link_name = "ImDrawList_AddTriangleFilled") draw_list_add_triangle_filled :: proc(self: ^DrawList, p1: [2]f32, p2: [2]f32, p3: [2]f32, col: U32) ---
	@(link_name = "ImDrawList_AddCircle") draw_list_add_circle :: proc(self: ^DrawList, center: [2]f32, radius: f32, col: U32) ---
	@(link_name = "ImDrawList_AddCircleEx") draw_list_add_circle_ex :: proc(self: ^DrawList, center: [2]f32, radius: f32, col: U32, num_segments: i32 = 0, thickness: f32 = 1.0, flags: DrawFlags = 0) ---
	@(link_name = "ImDrawList_AddCircleFilled") draw_list_add_circle_filled :: proc(self: ^DrawList, center: [2]f32, radius: f32, col: U32, num_segments: i32 = 0) ---
	@(link_name = "ImDrawList_AddText") draw_list_add_text :: proc(self: ^DrawList, pos: [2]f32, col: U32, text_begin: cstring) ---
	@(link_name = "ImDrawList_PathClear") draw_list_path_clear :: proc(self: ^DrawList) ---
	@(link_name = "ImDrawList_PathStroke") draw_list_path_stroke :: proc(self: ^DrawList, col: U32, thickness: f32 = 1.0, flags: DrawFlags = 0) ---
	@(link_name = "ImDrawList_PathArcTo") draw_list_path_arc_to :: proc(self: ^DrawList, center: [2]f32, radius: f32, a_min: f32, a_max: f32, num_segments: i32 = 0) ---
	@(link_name = "ImFontAtlas_AddFontDefault") font_atlas_add_font_default :: proc(self: ^FontAtlas, font_cfg: ^FontConfig = nil) -> ^Font ---
	@(link_name = "ImFontAtlas_AddFontFromFileTTF") font_atlas_add_font_from_file_ttf :: proc(self: ^FontAtlas, filename: cstring, size_pixels: f32 = 0.0, font_cfg: ^FontConfig = nil, glyph_ranges: ^Wchar = nil) -> ^Font ---
	@(link_name = "ImFontAtlas_AddFontFromMemoryTTF") font_atlas_add_font_from_memory_ttf :: proc(self: ^FontAtlas, font_data: rawptr, font_data_size: i32, size_pixels: f32 = 0.0, font_cfg: ^FontConfig = nil, glyph_ranges: ^Wchar = nil) -> ^Font ---
	@(link_name = "ImFontAtlas_Clear") font_atlas_clear :: proc(self: ^FontAtlas) ---
	@(link_name = "cImGui_ImplSDL3_InitForSDLGPU") sdl3_init_for_sdlgpu :: proc(window: ^sdl.Window) -> bool ---
	@(link_name = "cImGui_ImplSDL3_Shutdown") sdl3_shutdown :: proc() ---
	@(link_name = "cImGui_ImplSDL3_NewFrame") sdl3_new_frame :: proc() ---
	@(link_name = "cImGui_ImplSDL3_ProcessEvent") sdl3_process_event :: proc(event: ^sdl.Event) -> bool ---
	@(link_name = "cImGui_ImplSDLGPU3_Init") gpu3_init :: proc(info: ^ImplSDLGPU3_InitInfo) -> bool ---
	@(link_name = "cImGui_ImplSDLGPU3_Shutdown") gpu3_shutdown :: proc() ---
	@(link_name = "cImGui_ImplSDLGPU3_NewFrame") gpu3_new_frame :: proc() ---
	@(link_name = "cImGui_ImplSDLGPU3_PrepareDrawData") gpu3_prepare_draw_data :: proc(draw_data: ^DrawData, command_buffer: ^sdl.GPUCommandBuffer) ---
	@(link_name = "cImGui_ImplSDLGPU3_RenderDrawData") gpu3_render_draw_data :: proc(draw_data: ^DrawData, command_buffer: ^sdl.GPUCommandBuffer, render_pass: ^sdl.GPURenderPass) ---
}
