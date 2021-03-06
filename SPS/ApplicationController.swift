//
//  ApplicationController.swift
//  SPS
//
//  Created by Yaman JAIOUCH on 08/10/2016.
//  Copyright © 2016 Yaman JAIOUCH. All rights reserved.
//

import UIKit
import RxSwift
import Fabric
import Crashlytics
import UserNotifications

protocol ApplicationControllerType: UISplitViewControllerDelegate {
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]?) -> Bool
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool
    func applicationDidBecomeActive(_ application: UIApplication)
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
}

class ApplicationController: NSObject, ApplicationControllerType {
    
    // MARK: Properties
    
    private let disposeBag = DisposeBag()
    
    fileprivate let applicationRouter: ApplicationRouter
    private let proposalsStatusSynchronizer: ProposalsStatusSynchronizerType
    
    // MARK: Initializers
    
    init(splitViewController: UISplitViewController, proposalsStatusSynchronizer: ProposalsStatusSynchronizerType) {
        self.applicationRouter = ApplicationRouter(splitViewController: splitViewController)
        self.proposalsStatusSynchronizer = proposalsStatusSynchronizer
        
        super.init()
        
        self.applicationRouter.masterViewController.inject(proposalsStatusSynchronizer: proposalsStatusSynchronizer)
    }
    
    convenience init(splitViewController: UISplitViewController, proposalsStatusService: ProposalsStatusServiceType) {
        self.init(splitViewController: splitViewController,
                  proposalsStatusSynchronizer: ProposalsStatusSynchronizer(proposalsStatusService: proposalsStatusService))
    }
    
    // MARK: ApplicationControllerType conformance
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]?) -> Bool {
        // TODO: move to constants file
        let interval: TimeInterval
        #if DEBUG
        interval = UIApplicationBackgroundFetchIntervalMinimum
        #else
        interval = 60.0 * 60.0 * 2.0
        #endif
        
        application.setMinimumBackgroundFetchInterval(interval)
        
        UNUserNotificationCenter.current().delegate = self
        
        return true
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]?) -> Bool {
        Fabric.with([Crashlytics.self])
        
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
            .subscribe()
            .addDisposableTo(disposeBag)
        
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        let (observableFactory, _) = proposalsStatusSynchronizer.synchronize()
        observableFactory().subscribe()
            .addDisposableTo(disposeBag)
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let (factory, _) = proposalsStatusSynchronizer.synchronize()
        let observable = factory()
        observable.subscribe(
            onNext: { _ in
                completionHandler(.newData)
            },
            onError: { error in
                completionHandler(.failed)
            }
        )
        .addDisposableTo(disposeBag)
    }
}

extension ApplicationController: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let notification = response.notification.request.content.proposalStatusNotificationType else { return }
        
        applicationRouter.route(afterReceiving: notification)
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .badge, .sound])
    }
}
