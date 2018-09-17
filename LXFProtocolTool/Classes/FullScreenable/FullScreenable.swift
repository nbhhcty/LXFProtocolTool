//
//  FullScreenable.swift
//  LXFProtocolTool
//
//  Created by 林洵锋 on 2018/9/12.
//  Copyright © 2018年 LinXunFeng. All rights reserved.
//

/*
 *  使用说明：
 *  specifiedView所指向的view只能通过frame设置位置和大小，不要使用snapkit。(subView则随意)
 *
 *  请在 AppDelegate 中实现以下方法
 *
func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    if UIApplication.shared.lxf.allowRotation {
        return UIInterfaceOrientationMask.landscape
    }
    return .portrait
}
 */

private var lxf_isFullKey = "lxf_isFullKey"
private var lxf_specifiedViewKey = "lxf_specifiedViewKey"
private var lxf_superViewKey = "lxf_superViewKey"
private var lxf_selfFrameKey = "lxf_selfFrameKey"
private var lxf_allowRotationKey = "lxf_allowRotationKey"
private var lxf_defaultFullScreenableConfigKey = "lxf_defaultFullScreenableConfigKey"
private var lxf_vcFullScreenableConfigKey = "lxf_vcFullScreenableConfigKey"
private var lxf_appCurFullScreenableConfigKey = "lxf_appCurFullScreenableConfigKey"
private var lxf_orientationChangeBlockKey = "lxf_orientationChangeBlockKey"

public typealias FullScreenableCompleteType = (_ isFullScreen: Bool)->Void

// MARK:- FullScreenable
public protocol FullScreenable: AssociatedObjectStore, LXFCompatible { }
public extension LXFNameSpace where Base: FullScreenable {
    var isFullScreen: Bool {
        get { return base.associatedObject(forKey: &lxf_isFullKey, default: false) }
        set { base.setAssociatedObject(newValue, forKey: &lxf_isFullKey) }
    }
    
    fileprivate var lxf_specifiedView : UIView? {
        get { return base.associatedObject(forKey: &lxf_specifiedViewKey) }
        set { base.setAssociatedObject(newValue, forKey: &lxf_specifiedViewKey) }
    }
    
    fileprivate var lxf_superView : UIView? {
        get { return base.associatedObject(forKey: &lxf_superViewKey) }
        set { base.setAssociatedObject(newValue, forKey: &lxf_superViewKey) }
    }
    
    fileprivate var lxf_selfFrame : CGRect? {
        get { return base.associatedObject(forKey: &lxf_selfFrameKey) }
        set { base.setAssociatedObject(newValue, forKey: &lxf_selfFrameKey) }
    }
    
    fileprivate func lxf_switchFullScreen(isEnter: Bool? = nil, specifiedView: UIView?, superView: UIView?, config: FullScreenableConfig? = nil, completed: FullScreenableCompleteType?) {
        let config = config == nil ? FullScreenableConfig.defaultConfig() : config!
        let isEnter = isEnter == nil ? !isFullScreen : isEnter!
        
        // 开启/关闭屏幕旋转
        UIApplication.shared.lxf.allowRotation = isEnter
        
        UIView.animate(withDuration: config.animateDuration) {
            // 强制横竖屏
            let orientation: UIInterfaceOrientation = isEnter ? config.enterFullScreenOrientation : .portrait
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        }
        
        if isEnter { // 进入全屏
            if isFullScreen { return }
            // if specifiedView == nil { return }
            lxf_specifiedView = specifiedView
            lxf_superView = superView
            lxf_selfFrame = specifiedView?.frame
            
            specifiedView?.removeFromSuperview()
            if specifiedView != nil {
                UIApplication.shared.keyWindow?.addSubview(specifiedView!)
            }
            UIView.animate(withDuration: config.animateDuration, animations: {
                specifiedView?.frame = UIScreen.main.bounds
            }) { _ in
                guard let completed = completed else{ return }
                completed(isEnter)
            }
        } else { // 退出全屏
            if !isFullScreen { return }
            let specifiedView = self.lxf_specifiedView
            UIView.animate(withDuration: config.animateDuration, animations: {
                specifiedView?.frame = self.lxf_selfFrame ?? CGRect.zero
            }, completion: { _ in
                specifiedView?.removeFromSuperview()
                let superView = superView == nil ? self.lxf_superView : superView
                if specifiedView != nil {
                   superView?.addSubview(specifiedView!)
                }
                guard let completed = completed else{ return }
                completed(isEnter)
            })
        }
        isFullScreen = isEnter
    }
    
    func switchFullScreen(isEnter: Bool? = nil, specifiedView: UIView? = nil, superView: UIView? = nil, config: FullScreenableConfig? = nil, completed: FullScreenableCompleteType? = nil) {
        var specifiedView = specifiedView
        var superView = superView
        
        if let curView = base as? UIView {
            specifiedView = specifiedView == nil ? curView : specifiedView!
            superView = superView == nil ? curView.superview : superView!
        }
        
        lxf_switchFullScreen(
            isEnter: isEnter,
            specifiedView: specifiedView,
            superView: superView,
            config: config,
            completed: completed
        )
    }
}

extension FullScreenable {
    public func initAutoFullScreen() {
        DispatchQueue.once(token: "FullScreenable_lxf_SwizzledViewWillAppear") {
            LXFSwizzleMethod(
                originalCls: UIViewController.self,
                originalSelector: #selector(UIViewController.viewWillAppear(_:)),
                swizzledCls: UIViewController.self,
                swizzledSelector: #selector(UIViewController.lxf_viewWillAppear(_:)))
            
            LXFSwizzleMethod(
                originalCls: UIViewController.self,
                originalSelector: #selector(UIViewController.viewDidDisappear(_:)),
                swizzledCls: UIViewController.self,
                swizzledSelector: #selector(UIViewController.lxf_viewDidDisappear(_:)))
        }
    }
}

extension UIViewController: AssociatedObjectStore {
    var lxf_fullScreenableConfig: FullScreenableConfig {
        get { return associatedObject(forKey: &lxf_vcFullScreenableConfigKey, default: FullScreenableConfig.defaultConfig())}
        set { setAssociatedObject(newValue, forKey: &lxf_vcFullScreenableConfigKey) }
    }
    
    var lxf_orientationChangeBlock : (()->Void)? {
        get { return associatedObject(forKey: &lxf_orientationChangeBlockKey)}
        set { setAssociatedObject(newValue, forKey: &lxf_orientationChangeBlockKey) }
    }
    
    @objc func lxf_viewWillAppear(_ animated: Bool) {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lxf_orientationChangeNotification),
            name: .UIDeviceOrientationDidChange,
            object: nil)
        self.lxf_viewWillAppear(animated)
    }
    
    @objc func lxf_viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(
            self,
            name: .UIDeviceOrientationDidChange,
            object: nil)
        self.lxf_viewDidDisappear(animated)
    }
    
    @objc func lxf_orientationChangeNotification(){
        guard let block = lxf_orientationChangeBlock else { return }
        block()
    }
}

public extension LXFNameSpace where  Base : UIViewController, Base: FullScreenable {
    
    func enterFullScreen(specifiedView: UIView, config: FullScreenableConfig? = nil, completed: FullScreenableCompleteType? = nil) {
        switchFullScreen(
            isEnter: true,
            specifiedView: specifiedView,
            superView: nil,
            config: config,
            completed: completed
        )
    }
    
    func exitFullScreen(superView: UIView, config: FullScreenableConfig? = nil, completed: FullScreenableCompleteType? = nil) {
        switchFullScreen(
            isEnter: false,
            specifiedView: nil,
            superView: superView,
            config: config,
            completed: completed
        )
    }
    
    func autoFullScreen(specifiedView: UIView, superView: UIView) {
        base.initAutoFullScreen()
        base.lxf_orientationChangeBlock = {
            let orient = UIDevice.current.orientation
            switch orient {
            case .portrait :
                print("屏幕正常竖向")
                break
            case .portraitUpsideDown:
                print("屏幕倒立")
                break
            case .landscapeLeft:
                print("屏幕左旋转")
                break
            case .landscapeRight:
                print("屏幕右旋转")
                break
            default:
                break
            }
            self.switchFullScreen(
                isEnter: !self.isFullScreen,
                specifiedView: specifiedView,
                superView: superView)
        }
    }
}

public extension LXFNameSpace where Base : UIView, Base : FullScreenable {
    func enterFullScreen(specifiedView: UIView? = nil, config: FullScreenableConfig? = nil, completed: FullScreenableCompleteType? = nil) {
        switchFullScreen(
            isEnter: true,
            specifiedView: specifiedView,
            superView: nil,
            config: config,
            completed: completed
        )
    }
    
    func exitFullScreen(superView: UIView? = nil, config: FullScreenableConfig? = nil, completed: FullScreenableCompleteType? = nil) {
        switchFullScreen(
            isEnter: false,
            specifiedView: nil,
            superView: superView,
            config: config,
            completed: completed
        )
    }
}

// MARK:- UIApplication
extension UIApplication: AssociatedObjectStore, LXFCompatible { }
extension LXFNameSpace where Base : UIApplication {
    /// 控制屏幕旋转
    public var allowRotation: Bool {
        get { return UIApplication.shared.associatedObject(forKey: &lxf_allowRotationKey, default: false) }
        set {  UIApplication.shared.setAssociatedObject(newValue, forKey: &lxf_allowRotationKey) }
    }
    
    /// 当前全屏配置
    public var currentFullScreenConfig : FullScreenableConfig {
        get { return UIApplication.shared.associatedObject(forKey: &lxf_appCurFullScreenableConfigKey, default: FullScreenableConfig.defaultConfig()) }
        set { UIApplication.shared.setAssociatedObject(newValue, forKey: &lxf_appCurFullScreenableConfigKey) }
    }
    
    /// 当前控制器所支持的所有方向
    public var currentVcOrientationMask: UIInterfaceOrientationMask {
        if allowRotation {
            return .landscape
        }
        return .portrait
    }
}

public struct FullScreenableConfig {
    /// 全屏动画时间
    public var animateDuration: Double
    /// 进入全屏的初始方向
    public var enterFullScreenOrientation : UIInterfaceOrientation
    /// 全屏支持的所有方向
    public var supportInterfaceOrientation : UIInterfaceOrientationMask
    
    public init(
        animateDuration: Double = 0.25,
        enterFullScreenOrientation : UIInterfaceOrientation = .landscapeRight,
        supportInterfaceOrientation : UIInterfaceOrientationMask = .landscape
    ) {
        self.animateDuration = animateDuration
        self.enterFullScreenOrientation = enterFullScreenOrientation
        self.supportInterfaceOrientation = supportInterfaceOrientation
    }
    
    public static func setDefaultConfig(_ config: FullScreenableConfig) {
        UIApplication.shared.setAssociatedObject(
            config,
            forKey: &lxf_defaultFullScreenableConfigKey)
    }
    
    public static func defaultConfig() -> FullScreenableConfig {
        return UIApplication.shared.associatedObject(
            forKey: &lxf_defaultFullScreenableConfigKey,
            default: FullScreenableConfig())
    }
}

// MARK:- DispatchQueue
extension DispatchQueue {
    private static var _onceTracker = [String]()
    public class func once(token: String, block:()->Void) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        if _onceTracker.contains(token) { return }
        _onceTracker.append(token)
        block()
    }
}

// MARK:- Rumtime
fileprivate func LXFSwizzleMethod(originalCls: AnyClass?, originalSelector: Selector, swizzledCls: AnyClass?, swizzledSelector: Selector) {
    guard let originalMethod = class_getInstanceMethod(originalCls, originalSelector) else { return }
    guard let swizzledMethod = class_getInstanceMethod(swizzledCls, swizzledSelector) else { return }
    
    
    let didAddMethod = class_addMethod(originalCls,
                                       originalSelector,
                                       method_getImplementation(swizzledMethod),
                                       method_getTypeEncoding(swizzledMethod))
    
    if didAddMethod {
        class_replaceMethod(originalCls,
                            swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod))
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}
