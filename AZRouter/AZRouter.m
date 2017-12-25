/*******************************************************************************
 # File        : AZRouter.h
 # Project     : AZRouter_iOS
 # Author      : Andrew
 # Created     : 12/6/17
 # Description : 路由，负责分发页面跳转
 -------------------------------------------------------------------------------
 ******************************************************************************/

#import "AZRouter.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString * const kOpenRouteSchmem  = @"zshft";

NSString * const kRouterAdapter    = @"RouterAdapter";
NSString * const kStoryboard       = @"storyboard";
NSString * const kIdentifier       = @"identifier";
NSString * const kXibName          = @"nibname";
NSString * const kTargetClass      = @"targetclass";


NSString * const kObjectType       = @"ObjectType";
NSString * const kBoolType         = @"BoolType";
NSString * const kIntegerType      = @"IntegerType";
NSString * const kFolatType        = @"FolatType";

NSString * const kBoolTrue         = @"true";
NSString * const kBoolFalse        = @"false";

@interface AZRouter ()

@property (nonatomic, copy) NSString *routerScheme;
@property (nonatomic, strong)NSMutableArray *cacheUrlArray;

@end

@implementation AZRouter

/**
 路由单例对象
 
 @return 实例
 */
+ (instancetype)sharedInstance {
	static AZRouter *router = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		router = [AZRouter new];
        router.routerScheme = kOpenRouteSchmem;
	});
	return router;
}

- (void)configRouteScheme:(NSString *)scheme {
    self.routerScheme = scheme;
}

- (NSString *)scheme {
    return self.routerScheme;
}

- (BOOL)runRemoteUrl:(nullable NSString *)urlStr ParentVC:(nullable UIViewController *)vc {
	if (urlStr == nil) {
		return NO;
	}
	NSURL *url = [NSURL URLWithString:urlStr];
	if (url == nil) {
		return NO;
	}
	NSString *scheme = url.scheme;
	if (![scheme isEqualToString:self.routerScheme]) {
		// 不处理 非zshft scheme的URL
		return NO;
	}
	if (vc == nil) {
		// 当响应不存在时，此时就已经发生的 openurl ，所以将openurl 缓存起来
		if (self.cacheUrlArray.count>0) {
			[self.cacheUrlArray replaceObjectAtIndex:0 withObject:urlStr];
		} else {
			[self.cacheUrlArray addObject:urlStr];
		}
		return NO;
	}
	NSDictionary *params = [self parseURLParams:[url query]];
	NSString *host = url.host;
	if (!host || [host isEqualToString:@""]) {
		return NO;
	}
	[params setValue:url.absoluteString forKey:@"raw_url"];
	
	/*
		1. 优先查找对应的_RouterAdapter。因为有些页面跳转，不能简单的kvc，而是需要model传递，或者在跳转之前需要判断逻辑。
		   例如：会话聊天界面，需要传递 NIMSession 这个对象，这种情况，动态性不能满足需求，所以需要在本地的相关_RouterAdapter中，来进行转换。
		2. 如果没有找到对应的_RouterAdapter，那么则走runtime动态映射。
	 */

	Class adapterClass = NSClassFromString([self adapterNameByClassName:host]);
	if (adapterClass) {
		if ([adapterClass respondsToSelector:@selector(jumpRemoteWithParams:Parent:)]) {
			[adapterClass jumpRemoteWithParams:params Parent:vc];
			return YES;
		}
	}else{
		// runtime 动态
		NSString *targetVCStr = params[kTargetClass];
		if (targetVCStr) {
			UIViewController *targetVC = nil;
			if (params[kStoryboard]) {
				// 支持 Storyboard 获取控制器实例
				UIStoryboard *story = [UIStoryboard storyboardWithName:params[kStoryboard] bundle:[NSBundle mainBundle]];
				NSString *identifier = params[kIdentifier];
				targetVC = [story instantiateViewControllerWithIdentifier:identifier];
			}
			if (!targetVC) {
				// 尝试 xib 初始化
				if (params[kXibName]) {
					targetVC = [[NSClassFromString(targetVCStr) alloc] initWithNibName:params[kXibName] bundle:[NSBundle mainBundle]];
				}
			}
			if (!targetVC) {
				// 代码 创建控制器
				id obj = [NSClassFromString(targetVCStr) new];
				if (obj && [obj isKindOfClass:[UIViewController class]]) {
					targetVC = (UIViewController *)obj;
				}
			}
			if (!targetVC) {
				// 不存在oc下代码方式创建的vc, 再次考虑寻找swift下的vc，由于工程内，无swift文件，所以这里暂时未实现。
				return NO;
			}
			NSArray *propertyNameArray = [self propertyListByClass:NSClassFromString(targetVCStr)];
			@try {
				for (NSString *property in propertyNameArray) {
					NSString *key = [[property componentsSeparatedByString:@"-"] firstObject];
					NSString *type = [[property componentsSeparatedByString:@"-"] lastObject];
					if (params[key]) {
						// 32位操作系统，iphone5 没有该 [__NSCFString charValue]
						if ([type isEqualToString:kBoolType]) {
							NSInteger boolEle = 0;
							// 兼容 true 和 false
							if ([params[key] isEqualToString:kBoolTrue]) {
								boolEle = 1;
							}else if ([params[key] isEqualToString:kBoolFalse]) {
								boolEle = 0;
							}else {
								boolEle = [params[key] integerValue];
							}
							[targetVC setValue:@(boolEle) forKey:key];
						}else{
							[targetVC setValue:params[key] forKey:key];
						}
					}
				}
                [vc.navigationController pushViewController:targetVC animated:YES];
                
			} @catch (NSException *exception) {
				NSLog(@"处理远程url，动态跳转异常。-- %@",exception);
			} @finally {
				return YES;
			}
		}
	}
	
	return NO;

}


-(nullable id)runNativeTarget:(NSString *)targetName Action:(NSString *)actionName Params:(NSDictionary *)params {
	NSObject *target = target = [NSClassFromString(targetName) new];
	if (!target) {
		// 仍然没有该目标对象
		return nil;
	}
	SEL action = NSSelectorFromString(actionName);
	if ([target respondsToSelector:action]) {
		return [self safeRunTarget:target Action:action Params:params];
	}else{
		// 有可能target是Swift对象
		actionName = [NSString stringWithFormat:@"%@WithParams:", actionName];
		action = NSSelectorFromString(actionName);
		if ([target respondsToSelector:action]) {
			return [self safeRunTarget:target Action:action Params:params];
		} else {
			// 这里是处理无响应请求的地方，如果无响应，则尝试调用对应target的notFoundAction方法统一处理
			SEL action = NSSelectorFromString(@"notFoundAction:");
			if ([target respondsToSelector:action]) {
				return [self safeRunTarget:target Action:action Params:params];
			} else {
				
				return nil;
			}
		}
	}
	
	
	return nil;
}



- (void)handleCacheRemoteURL {
	for (int i=0; i<_cacheUrlArray.count; i++) {
		NSString *urlStr = _cacheUrlArray[i];
		[self runRemoteUrl:urlStr ParentVC:[self appFirstViewController]];
	}
	[_cacheUrlArray removeAllObjects];
}

#pragma mark - private

- (NSDictionary *)parseURLParams:(NSString *)query {
 
	NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2) {
            NSString *key = [[kv firstObject] stringByRemovingPercentEncoding];
            NSString *value = [[kv lastObject] stringByRemovingPercentEncoding];
            
            // array name[0]=xx name[1]=xx  dictionary person[name]='zhangsan' person[age]=21
            if ([key containsString:@"["] && [key hasSuffix:@"]"]){
                
                @try {
                    
                    NSString *objName = [key substringToIndex:[key rangeOfString:@"["].location];
                    NSString *objValue = value;
                    NSString *type = [[key substringFromIndex:[key rangeOfString:@"["].location+1] stringByReplacingOccurrencesOfString:@"]" withString:@""];
                    
                    if ([self isPureInt:type]) {
                        // array type
                        NSMutableArray *tempArray = [[params objectForKey:objName] mutableCopy];
                        if (!tempArray) {
                            tempArray = [NSMutableArray array];
                        }
                        [tempArray addObject:objValue];
                        [params setObject:tempArray forKey:objName];
                    } else {
                        // diction type
                        NSString *objKey = type;
                        NSMutableDictionary *tempDic = [[params objectForKey:objName] mutableCopy];
                        if (!tempDic) {
                            tempDic = [NSMutableDictionary dictionary];
                        }
                        [tempDic setObject:objValue forKey:objKey];
                        [params setObject:tempDic forKey:objName];
                    }

                } @catch (NSException *exception) {
                    NSLog(@"%@",exception);
                } @finally {
                    // nothing to do
                }
            } else {
                
               [params setObject:value forKey:key];
            }
        }
    }
	
	return params;
}

- (BOOL)isPureInt:(NSString*)string{
    NSScanner* scan = [NSScanner scannerWithString:string];
    int val;
    return[scan scanInt:&val] && [scan isAtEnd];
}

- (nullable UIViewController *)appFirstViewController {
    
    UIViewController *result = nil;
    UIWindow * window = [[UIApplication sharedApplication] keyWindow];
    if (window.windowLevel != UIWindowLevelNormal){
        NSArray *windows = [[UIApplication sharedApplication] windows];
        for(UIWindow * tmpWin in windows){
            if (tmpWin.windowLevel == UIWindowLevelNormal){
                window = tmpWin;
                break;
            }
        }
    }
    
    UIView *frontView = [[window subviews] objectAtIndex:0];
    id nextResponder = [frontView nextResponder];
    if ([nextResponder isKindOfClass:[UIViewController class]]) {
        result = nextResponder;
    } else {
        result = window.rootViewController;
    }
    // 兼容自定义 RDVTabBarController
    if ([result.childViewControllers count] > 0) {
        result = [result.childViewControllers firstObject];
    }
    if ([result isKindOfClass:[UITabBarController class]]) {
        UIViewController *tempVC = [[(UITabBarController *)result viewControllers] firstObject];
        result = tempVC;
    }
    if ([result isKindOfClass:[UINavigationController class]]) {
        UIViewController *tempVC = [[(UINavigationController *)result viewControllers] firstObject];
        result = tempVC;
    }
    return result;
}

- (NSString *)adapterNameByClassName:(NSString *)className {
	NSString *name = [className copy];
	NSArray *ary = [name componentsSeparatedByString:@"."];
	NSString *class_name = @"";
	for (NSString *eleName in ary) {
		NSString *tempName = @"";
		tempName = [eleName lowercaseString];
		tempName = [NSString stringWithFormat:@"%@%@",[[eleName substringToIndex:1] uppercaseString],[eleName substringWithRange:NSMakeRange(1, eleName.length-1)]];
		class_name = [class_name stringByAppendingString:tempName];
	}
	NSString *adapterName = [NSString stringWithFormat:@"%@_%@",class_name,kRouterAdapter];
	return adapterName;
}

- (NSArray *)propertyListByClass:(Class)class {
	NSMutableArray *propertyArray = [NSMutableArray array];
	
	// 获取当前类和基类的所有属性，直到 NSObject 结束
	while (class != [NSObject class]) {
		
		unsigned int outCount = 0;
		objc_property_t * properties = class_copyPropertyList(class, &outCount);
		
		for (unsigned int i = 0; i < outCount; i ++) {
			
			objc_property_t property = properties[i];
			// property名
			const char * name = property_getName(property);
			NSString * propertyName = [NSString stringWithUTF8String:name];
			
			
			// property属性配置
			const char * nameAttribute = property_getAttributes(property);
			NSString * propertyAttribute = [NSString stringWithUTF8String:nameAttribute];
			NSString * firstStr = [[propertyAttribute componentsSeparatedByString:@","] firstObject];
			NSString * typeStr = firstStr.length >= 2 ? [firstStr substringWithRange:NSMakeRange(1, 1)]:nil;
			// bool--Tc NSInteger--Ti CGFloat--Tf
			
			NSString * appenStr = @"";
			if ([typeStr containsString:@"@"]) {
				appenStr = [NSString stringWithFormat:@"-%@",kObjectType];
			}else if ([typeStr isEqualToString:@"c"] || [typeStr isEqualToString:@"C"]) {
				appenStr = [NSString stringWithFormat:@"-%@",kBoolType];;
			}else if ([typeStr isEqualToString:@"i"] || [typeStr isEqualToString:@"I"]) {
				appenStr = [NSString stringWithFormat:@"-%@",kIntegerType];
			}else if ([typeStr isEqualToString:@"f"] || [typeStr isEqualToString:@"F"]) {
				appenStr = [NSString stringWithFormat:@"-%@",kFolatType];
			}
			propertyName = [propertyName stringByAppendingString:appenStr];
			[propertyArray addObject:propertyName];
		}
		free(properties);
		class = class_getSuperclass(class);
	}
	
	return [propertyArray copy];
}

-(id)safeRunTarget:(NSObject *)target Action:(SEL)action Params:(NSDictionary *)params {
	NSMethodSignature* methodSig = [target methodSignatureForSelector:action];
	if(methodSig == nil) {
		return nil;
	}
	const char* retType = [methodSig methodReturnType];
	
	if (strcmp(retType, @encode(void)) == 0) {
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
		[invocation setArgument:&params atIndex:2];
		[invocation setSelector:action];
		[invocation setTarget:target];
		[invocation invoke];
		return nil;
	} else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		return [target performSelector:action withObject:params];
#pragma clang diagnostic pop
	}
}


#pragma mark - lazy load
- (NSMutableArray *)cacheUrlArray {
	if (!_cacheUrlArray) {
		_cacheUrlArray = [NSMutableArray arrayWithCapacity:1];
	}
	return _cacheUrlArray;
}

@end



#pragma mark - AZRouter(Host)

@implementation AZRouter(Host)

- (NSString *)urlRemoteHost:(NSString *)host Params:(nullable NSDictionary *)params {
	return [NSString stringWithFormat:@"%@://%@%@",[AZRouter sharedInstance].scheme,host,[[AZRouter sharedInstance]queryWithDictionary:params]];
}

- (NSString *)urlDynamicTargetClassName:(NSString *)targetClass Storyboard:(nullable NSString *)storyname Identifier:(nullable NSString *)identifier XibName:(nullable NSString *)xibName Params:(nullable NSDictionary *)params {
	NSMutableDictionary *mutableDic = [NSMutableDictionary dictionary];
	[mutableDic setObject:targetClass forKey:kTargetClass];
	if (storyname) {
		[mutableDic setObject:storyname forKey:kStoryboard];
	}
	if (identifier) {
		[mutableDic setObject:identifier forKey:kIdentifier];
	}
	if (xibName) {
		[mutableDic setObject:xibName forKey:kXibName];
	}
	if (params) {
		[mutableDic setValuesForKeysWithDictionary:params];
	}
	NSString *paramurl = [[AZRouter sharedInstance] queryWithDictionary:[mutableDic copy]];
	return [NSString stringWithFormat:@"%@://%@%@",[AZRouter sharedInstance].scheme,@"com.dynamic",paramurl];
}

- (NSString *)queryWithDictionary:(nullable NSDictionary *)params {
	NSString *query = @"";
	if (!params) {
		return query;
	}
	for (NSString *key in params.allKeys) {
		NSObject *obj = params[key];
		if ([obj isKindOfClass:[NSString class]]) {
			query = [query stringByAppendingString:[NSString stringWithFormat:@"%@=%@&",key,(NSString *)obj]];
		}else if ([obj isKindOfClass:[NSNumber class]]){
			query = [query stringByAppendingString:[NSString stringWithFormat:@"%@=%ld&",key,(long)[(NSNumber *)obj integerValue]]];
		}else {
			NSLog(@"params 含有其他类型，建议使用 NSString");
		}
	}
	if ([query hasSuffix:@"&"]) {
		query = [NSString stringWithFormat:@"?%@",query];
		query = [query substringToIndex:query.length-1];
	}
	return query;
}

@end
