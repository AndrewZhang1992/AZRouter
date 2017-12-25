/*******************************************************************************
 # File        : AZRouter.h
 # Project     : AZRouter_iOS
 # Author      : Andrew
 # Created     : 12/6/17
 # Description : 路由，负责分发页面跳转
 -------------------------------------------------------------------------------
 ******************************************************************************/

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// app可使用 scheme 属性读取
extern NSString * const kOpenRouteSchmem;


#pragma mark -  AZRouterProtrol

@protocol AZRouterProtrol<NSObject>

@required
/**
 远程调用 跳转

 @param params NSDictionary
 @param vc 响应根控制器
 */
+ (void)jumpRemoteWithParams:(NSDictionary *)params Parent:(UIViewController *)vc;

@end



#pragma mark -  AZRouter
@interface AZRouter : NSObject

/**
 scheme
 */
@property (nonatomic, copy, readonly) NSString *scheme;


/**
 路由单例对象

 @return 实例
 */
+ (instancetype)sharedInstance;


/**
 配置路由scheme  default: zshft
 
 @desc: 在 didFinishLaunchingWithOptions: 中设置 或者 在mian.m 中设置，
        保证程序刚启动就已经配置完成。
        app必须参考上述设置。
 */
- (void)configRouteScheme:(NSString *)scheme;

/**
 处理 远程 open Url
 
 @param url url 例如：zshft://house.detail?caseId=6632361&caseType=1&bizType=1
 @param vc 响应跳转的根视图
 @return bool
 
 @desc:
    当 vc = nil，内部会将这次的路由跳转缓存起来,在能够处理响应的时候，调用 handleCacheOpenURL。
    query 支持 数组 字典类型。例如: zshft://com.abc?city[0]=beijing&city[2]=shanghai&city[3]=hangzhou&person[name]=li&person[age]=21&id=53278
 
 @use scene:
    例如: apns推送，app 收到推送，需要处理url跳转，但是此刻app，可能刚被唤醒，所以可以当app 启动完成，进入第一个vc之后，再去处理响应。
 */
- (BOOL)runRemoteUrl:(nullable NSString *)urlStr ParentVC:(nullable UIViewController *)vc;

/**
 调用 本地 native 方法
 
 @desc: 使用于 组件化跨模块的方式 调用，基本不会在业务层直接调用，该方法主要用于组件化解耦，采用 target-action 模式，
		具体组件化实际调用流程： 1. 每个组件内部，有两个文件（ AZRouter+ModuleName.h  Target_ModuleName.h）
							  这两个文件是组件内部的通信子module,组件内部的跳转也可以使用这两个文件.
						    2. 跨越组件通信的时候，以 AZRouter 为底层通信处理，以内部通信组件为对接。
 
 @param targetName  目标类名（字符串）
 @param actionName  方法名 （字符串）
 @param params      传递参数 （k-v）
 @return id 类型
 */
- (nullable id)runNativeTarget:(NSString *)targetName Action:(NSString *)actionName Params:(nullable NSDictionary *)params;


/**
 处理缓存 url
 */
- (void)handleCacheRemoteURL;

@end


#pragma mark - AZRouter (Host)

@interface AZRouter (Host)

/**
 生成 远程 url

 @param host host 例如：im.detail
 @param params 参数
 @return url
 */
- (NSString *)urlRemoteHost:(NSString *)host Params:(nullable NSDictionary *)params;


/**
 生成 动态调用的远程 url

 @param targetClass 目标类名
 @param storyname storyname 非storyname启动，则为nil
 @param identifier identifier
 @param xibName xib文件名
 @param params 参数
 @return url
 
 @desc: 
 示例
 NSString *url = [AZRouter urlDynamicTargetClassName:@"SosoDetailInfoViewController" Storyboard:@"SosoDetailInfoViewController" Identifier:@"SosoDetailInfoViewController" Params:@{@"houseId":@"1011097221",@"houseInfoState":@"0",@"isFromHome":@"1"}];

 获取到 zshft://com.dynamic?storyboard=SosoDetailInfoViewController&targetclass=SosoDetailInfoViewController&houseInfoState=0&identifier=SosoDetailInfoViewController&houseId=1011097221&isFromHome=1
 
 */
- (NSString *)urlDynamicTargetClassName:(NSString *)targetClass Storyboard:(nullable NSString *)storyname Identifier:(nullable NSString *)identifier XibName:(nullable NSString *)xibName Params:(nullable NSDictionary *)params;


@end


NS_ASSUME_NONNULL_END
