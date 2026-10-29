//
//  PiPManager.m
//  LiveContainer
//
//  Created by s s on 2025/6/3.
//
#include "PiPManager.h"
#include "AppSceneViewController.h"
#include "DecoratedAppSceneViewController.h"
#include "../LiveContainer/utils.h"

API_AVAILABLE(ios(16.0))
@interface PiPManager()
@property(nonatomic, strong) UIView *pipVideoCallContentView;
@property(nonatomic, strong) AVPictureInPictureVideoCallViewController *pipVideoCallViewController;
@property(nonatomic, strong) AVPictureInPictureController *pipController;
@property(nonatomic) AppSceneViewController* displayingVC;
@end


@implementation PiPManager
API_AVAILABLE(ios(16.0))
static PiPManager* sharedInstance = nil;

+ (instancetype)shared {
    if(!sharedInstance)
        sharedInstance = [[self alloc] init];
    return sharedInstance;
}

- (DecoratedAppSceneViewController *)displayingDecoratedVC {
    return (id)self.displayingVC.delegate;
}

- (BOOL)isPiP {
    return self.pipController.isPictureInPictureActive;
}

- (BOOL)isPiPWithVC:(AppSceneViewController*)vc {
    return self.pipController.isPictureInPictureActive && self.displayingVC == vc;
}

- (BOOL)isPiPWithDecoratedVC:(UIViewController*)vc {
    return self.pipController.isPictureInPictureActive && self.displayingDecoratedVC == vc;
}

- (instancetype)init {
    NSError* error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    [[AVAudioSession sharedInstance] setActive:YES withOptions:1 error:&error];
    return self;
}

- (void)startPiPWithVC:(AppSceneViewController*)vc {
    [self.pipController stopPictureInPicture];
    if(self.displayingVC) {
        [self.displayingDecoratedVC unminimizeWindowPiP];
        [self pictureInPictureControllerDidStopPictureInPicture:self.pipController];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([self.pipController isPictureInPictureActive] * 0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.displayingVC = vc;
        self.pipVideoCallViewController = [AVPictureInPictureVideoCallViewController new];
        self.pipVideoCallViewController.preferredContentSize = vc.view.bounds.size;
        // 画面的挂载必须早于 startPictureInPicture，否则 PiP 窗口会起来但内容层为空，
        // 表现就是「只有声音没有画面」。这里在创建 contentSource 前就把内容视图准备好。
        if(vc.usesHostingControllerAPI) {
            self.pipVideoCallContentView = [[UIView alloc] initWithFrame:vc.view.bounds];
            self.pipVideoCallContentView.layer.anchorPoint = CGPointMake(0, 0);
            self.pipVideoCallContentView.layer.position = CGPointMake(0, 0);
            self.pipVideoCallContentView.clipsToBounds = YES;
            [self.pipVideoCallViewController.view addSubview:self.pipVideoCallContentView];
            vc.contentView.frame = self.pipVideoCallContentView.bounds;
            [self.pipVideoCallContentView addSubview:vc.contentView];
        } else {
            self.pipVideoCallContentView = vc.contentView;
        }
        AVPictureInPictureControllerContentSource* contentSource =  [[AVPictureInPictureControllerContentSource alloc] initWithActiveVideoCallSourceView:vc.view contentViewController:self.pipVideoCallViewController];
        self.pipController = [[AVPictureInPictureController alloc] initWithContentSource:contentSource];
        self.pipController.canStartPictureInPictureAutomaticallyFromInline = YES;
        self.pipController.delegate = self;
        [self.pipController setValue:@1 forKey:@"controlsStyle"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.pipController startPictureInPicture];
        });
    });

}

- (void)stopPiP {
    [self.pipController stopPictureInPicture];
}

// PIP delegate
- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    [self.displayingDecoratedVC minimizeWindowPiP];
    if(self.displayingVC.usesHostingControllerAPI) {
        // 尺寸可能因为方向或 PiP 容器变化而不同步，这里强制重算一次，
        // 避免 contentView 仍按 0 尺寸或旧尺寸布局。
        CGRect target = self.pipVideoCallViewController.view.bounds;
        if(target.size.width <= 0 || target.size.height <= 0) {
            target = self.displayingVC.view.bounds;
        }
        self.pipVideoCallContentView.frame = target;
        self.pipVideoCallViewController.additionalSafeAreaInsets = self.displayingVC.view.safeAreaInsets;
        if(self.displayingVC.contentView.superview != self.pipVideoCallContentView) {
            [self.pipVideoCallContentView addSubview:self.displayingVC.contentView];
        }
        self.displayingVC.contentView.frame = self.pipVideoCallContentView.bounds;
    } else {
        self.displayingVC.contentView.frame = CGRectMake(0, 0, self.displayingVC.view.bounds.size.width, self.displayingVC.view.bounds.size.height);
    }
    if(self.pipVideoCallContentView.superview != self.pipVideoCallViewController.view) {
        [self.pipVideoCallViewController.view addSubview:self.pipVideoCallContentView];
    }
    [self.pipVideoCallViewController.view.layer removeObserver:self forKeyPath:@"bounds"];
    [self.pipVideoCallViewController.view.layer addObserver:self
                                forKeyPath:@"bounds"
                                   options:NSKeyValueObservingOptionNew
                                   context:NULL];
    if(self.displayingVC.view.bounds.size.width > 0 && self.displayingVC.view.bounds.size.height > 0) {
        self.pipVideoCallViewController.preferredContentSize = self.displayingVC.view.bounds.size;
    }
    [self.displayingVC setBackgroundNotificationEnabled:false];
    self.displayingVC.shouldIgnoreSceneUpdates = YES;
}



- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    
}

- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    self.displayingVC.shouldIgnoreSceneUpdates = NO;
    [self.displayingDecoratedVC unminimizeWindowPiP];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    @try {
        [self.pipVideoCallViewController.view.layer removeObserver:self forKeyPath:@"bounds"];
    } @catch (__unused NSException *exception) {
        // 观察者可能已被移除，忽略即可。
    }
    [self.displayingVC.view insertSubview:self.displayingVC.contentView atIndex:0];
    [self.displayingVC setBackgroundNotificationEnabled:true];
    // resize if needed (eg orientation differs)
    [self.displayingDecoratedVC updateVerticalConstraints];
    
    self.pipVideoCallContentView.transform = CGAffineTransformIdentity;
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCAutoEndPiP"]) {
        self.pipController = nil;
        self.pipVideoCallViewController = nil;
    }
    // FIXME: HostingController path causes a tiny flicker during transition to and from PiP.
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
    NSLog(@"%@", error.description);
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(NSObject*)object change:(NSDictionary<NSString *,id> *) change context:(void *) context {
    CGRect rect = [change[@"new"] CGRectValue];
    CGFloat sourceW = self.displayingVC.contentView.bounds.size.width;
    CGFloat sourceH = self.displayingVC.contentView.bounds.size.height;
    // 源尺寸为 0 时直接返回，否则会算出 inf/NaN 的 transform，把内容层推出可视区域。
    if(sourceW <= 0 || sourceH <= 0 || rect.size.width <= 0 || rect.size.height <= 0) return;
    CGFloat scale = self.displayingVC.usesHostingControllerAPI ? self.displayingVC.scaleRatio : 1;
    if(scale <= 0) scale = 1;
    CGAffineTransform transform1 = CGAffineTransformScale(CGAffineTransformIdentity, rect.size.width / sourceW / scale, rect.size.height / sourceH / scale);
    self.pipVideoCallContentView.transform = transform1;
    self.pipVideoCallViewController.preferredContentSize = rect.size;
}

@end
