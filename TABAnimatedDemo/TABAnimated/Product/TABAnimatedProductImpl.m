//
//  TABAnimatedProductImpl.m
//  AnimatedDemo
//
//  Created by tigerAndBull on 2020/4/1.
//  Copyright © 2020 tigerAndBull. All rights reserved.
//

#import "TABAnimatedProductImpl.h"
#import "TABAnimatedProductHelper.h"
#import "TABAnimatedProduction.h"

#import "TABViewAnimated.h"
#import "UIView+TABControlModel.h"

#import "TABAnimatedDarkModeInterface.h"
#import "TABComponentLayer.h"
#import "TABWeakDelegateManager.h"
#import "TABAnimatedCacheManager.h"

#import "UIView+TABAnimatedProduction.h"

#import "TABAnimatedDarkModeManagerImpl.h"
#import "TABAnimatedChainManagerImpl.h"
#import "TABAnimationManagerImpl.h"

#import "TABAnimated.h"

@interface TABAnimatedProductImpl() {
    // self存在即存在
    __unsafe_unretained UIView *_controlView;
    // 进入加工流时，会取出targetView，结束时释放。加工流只会在持有targetView的controlView存在时执行。
    __unsafe_unretained UIView *_targetView;
}

// 加工等待队列
@property (nonatomic, strong) NSPointerArray *weakTargetViewArray;

// 正在生产的index，配合targetViewArray实现加工等待队列
@property (nonatomic, assign) NSInteger productIndex;
// 正在生成的子view的tagIndex
@property (nonatomic, assign) NSInteger targetTagIndex;

// 产品复用池
@property (nonatomic, strong) NSMutableDictionary <NSString *, TABAnimatedProduction *> *productionPool;

// 生产结束，将产品同步给等待中的view
@property (nonatomic, assign) BOOL productFinished;

// 模式切换协议
@property (nonatomic, strong) id <TABAnimatedDarkModeManagerInterface> darkModeManager;

// 链式调整协议
@property (nonatomic, strong) id <TABAnimatedChainManagerInterface> chainManager;

// 动画管理协议
@property (nonatomic, strong) id <TABAnimationManagerInterface> animationManager;

@end

@implementation TABAnimatedProductImpl

- (instancetype)init {
    if (self = [super init]) {
        if ([TABAnimated sharedAnimated].darkModeType == TABAnimatedDarkModeBySystem) {
            _darkModeManager = TABAnimatedDarkModeManagerImpl.new;
        }
        _animationManager = TABAnimationManagerImpl.new;
        _weakTargetViewArray = [NSPointerArray weakObjectsPointerArray];
    }
    return self;
}

#pragma mark - TABAnimatedProductInterface

- (__kindof UIView *)productWithControlView:(UIView *)controlView
                               currentClass:(Class)currentClass
                                  indexPath:(nullable NSIndexPath *)indexPath
                                     origin:(TABAnimatedProductOrigin)origin {
    
    if (_controlView == nil) {
        [self setControlView:controlView];
    }
    
    NSString *className = tab_NSStringFromClass(currentClass);
    NSString *controllerClassName = controlView.tabAnimated.targetControllerClassName;
    UIView *view;
    
    NSString *key = [TABAnimatedProductHelper getKeyWithControllerName:controllerClassName targetClass:currentClass frame:controlView.frame];
    TABAnimatedProduction *production;
    
    if (!_controlView.tabAnimated.containNestAnimation) {
        // 缓存
        production = [[TABAnimatedCacheManager shareManager] getProductionWithKey:key];
        if (production) {
            view = [self _reuseWithCurrentClass:currentClass indexPath:indexPath origin:origin className:className production:production];
            return view;
        }
    }

    // 生产
    production = [self.productionPool objectForKey:className];
    if (production == nil || _controlView.tabAnimated.containNestAnimation) {
        view = [self _createViewWithOrigin:origin controlView:controlView indexPath:indexPath className:className currentClass:currentClass isNeedProduct:YES];
        [self _prepareProductWithView:view currentClass:currentClass indexPath:indexPath origin:origin needSync:YES needReset:_controlView.tabAnimated.containNestAnimation];
        return view;
    }
    
    // 复用
    view = [self _reuseWithCurrentClass:currentClass indexPath:indexPath origin:origin className:className production:production];
    return view;
}

- (void)productWithView:(nonnull UIView *)view
            controlView:(nonnull UIView *)controlView
           currentClass:(nonnull Class)currentClass
              indexPath:(nullable NSIndexPath *)indexPath
                 origin:(TABAnimatedProductOrigin)origin {
    
    if (_controlView == nil) {
        [self setControlView:controlView];
    }
    
    NSString *controlerClassName = controlView.tabAnimated.targetControllerClassName;
    NSString *key = [TABAnimatedProductHelper getKeyWithControllerName:controlerClassName targetClass:currentClass frame:controlView.frame];
    TABAnimatedProduction *production = [[TABAnimatedCacheManager shareManager] getProductionWithKey:key];
    if (production) {
        TABAnimatedProduction *newProduction = production.copy;
        [self _bindWithProduction:newProduction targetView:view];
        return;
    }
    
    [self _prepareProductWithView:view currentClass:currentClass indexPath:indexPath origin:origin needSync:NO needReset:YES];
}

- (void)pullLoadingProductWithView:(nonnull UIView *)view
                       controlView:(nonnull UIView *)controlView
                      currentClass:(nonnull Class)currentClass
                         indexPath:(nullable NSIndexPath *)indexPath
                            origin:(TABAnimatedProductOrigin)origin {
    
    if (_controlView == nil) [self setControlView:controlView];
    
    NSString *controlerClassName = controlView.tabAnimated.targetControllerClassName;
    NSString *key = [TABAnimatedProductHelper getKeyWithControllerName:controlerClassName targetClass:currentClass frame:controlView.frame];
    TABAnimatedProduction *production = [[TABAnimatedCacheManager shareManager] getProductionWithKey:key];
    if (production) {
        TABAnimatedProduction *newProduction = production.copy;
        [self _bindWithProduction:newProduction targetView:view];
        return;
    }
    
    NSString *className = tab_NSStringFromClass(currentClass);
    production = [self.productionPool objectForKey:className];
    if (production == nil || _controlView.tabAnimated.containNestAnimation) {
        UIView *newView = currentClass.new;
        newView.frame = CGRectMake(0, 0, TABAnimatedProductHelperScreenWidth, ((TABFormAnimated *)controlView.tabAnimated).pullLoadingComponent.viewHeight);
        [view addSubview:newView];
        [self _prepareProductWithView:newView currentClass:currentClass indexPath:indexPath origin:origin needSync:YES needReset:NO];
        return;
    }
    
    [self _reuseProduction:production targetView:view];
}

// 同步
- (void)syncProductions {
    for (NSInteger i = 0; i < self.weakTargetViewArray.count; i++) {
        UIView *view = [self.weakTargetViewArray pointerAtIndex:i];
        if (!view) return;
        view.hidden = NO;
        [self _bindWithProduction:view.tabAnimatedProduction targetView:view];
        [self _syncProduction:view.tabAnimatedProduction];
    }
    [self _recoveryProductStatus];
}

- (void)destory {
    [self _recoveryProductStatus];
    [self.darkModeManager destroy];
}

#pragma mark - Private

- (void)_recoveryProductStatus {
    _weakTargetViewArray = [NSPointerArray weakObjectsPointerArray];
    _productIndex = 0;
    _targetTagIndex = 0;
    _productFinished = NO;
}

- (void)_prepareProductWithView:(UIView *)view currentClass:(Class)currentClass indexPath:(nullable NSIndexPath *)indexPath origin:(TABAnimatedProductOrigin)origin needSync:(BOOL)needSync needReset:(BOOL)needReset {
    TABAnimatedProduction *production = view.tabAnimatedProduction;
    if (production == nil) {
        production = [TABAnimatedProduction productWithState:TABAnimatedProductionCreate];
        NSString *className = tab_NSStringFromClass(view.class);
        view.tabAnimatedProduction = production;
        if (needSync) {
            [self.productionPool setObject:production forKey:className];
        }
    }
    production.targetClass = currentClass;
    production.currentSection = indexPath.section;
    production.currentRow = indexPath.row;
    
    [self _productBackgroundLayerWithView:view needReset:needReset];
}

- (__kindof UIView *)_reuseWithCurrentClass:(Class)currentClass
                                  indexPath:(nullable NSIndexPath *)indexPath
                                     origin:(TABAnimatedProductOrigin)origin
                                  className:(NSString *)className
                                 production:(TABAnimatedProduction *)production {
    UIView *view = [self _createViewWithOrigin:origin controlView:_controlView indexPath:indexPath className:className currentClass:currentClass isNeedProduct:NO];
    if (view.tabAnimatedProduction) return view;
    [self _reuseProduction:production targetView:view];
    return view;
}

- (__kindof UIView *)_createViewWithOrigin:(TABAnimatedProductOrigin)origin
                               controlView:(UIView *)controlView
                                 indexPath:(nullable NSIndexPath *)indexPath
                                 className:(NSString *)className
                              currentClass:(Class)currentClass
                             isNeedProduct:(BOOL)isNeedProduct {
    
    NSString *prefixString = isNeedProduct ? @"tab_" : @"tab_contain_";
    NSString *identifier = [NSString stringWithFormat:@"%@%@", prefixString, className];
    UIView *view;
    
    switch (origin) {
            
        case TABAnimatedProductOriginTableViewCell: {
            view = [(UITableView *)controlView dequeueReusableCellWithIdentifier:identifier forIndexPath:indexPath];
            ((UITableViewCell *)view).selectionStyle = UITableViewCellSelectionStyleNone;
            view.backgroundColor = controlView.tabAnimated.animatedBackgroundColor;
        }
            break;
            
        case TABAnimatedProductOriginCollectionViewCell: {
            view = [(UICollectionView *)controlView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
            view.backgroundColor = controlView.tabAnimated.animatedBackgroundColor;
        }
            break;
            
        case TABAnimatedProductOriginCollectionReuseableHeaderView: {
            view = [(UICollectionView *)controlView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                                                       withReuseIdentifier:identifier
                                                                              forIndexPath:indexPath];
            view.backgroundColor = controlView.tabAnimated.animatedBackgroundColor;
        }
            break;
            
        case TABAnimatedProductOriginCollectionReuseableFooterView: {
            view = [(UICollectionView *)controlView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                                                                       withReuseIdentifier:identifier
                                                                              forIndexPath:indexPath];
            view.backgroundColor = controlView.tabAnimated.animatedBackgroundColor;
        }
            break;
            
        case TABAnimatedProductOriginTableHeaderFooterViewCell: {
            view = [(UITableView *)controlView dequeueReusableHeaderFooterViewWithIdentifier:identifier];
            if (view == nil) {
                view = [[currentClass alloc] initWithReuseIdentifier:identifier];
            }
            view.backgroundColor = controlView.tabAnimated.animatedBackgroundColor;
        }
            break;
            
        default: {
            view = NSClassFromString(className).new;
        }
            break;
    }
    return view;
}

- (void)_reuseProduction:(TABAnimatedProduction *)production targetView:(UIView *)targetView {
    TABAnimatedProduction *newProduction = production.copy;
    if (production.state != TABAnimatedProductionCreate) {
        [self _bindWithProduction:newProduction targetView:targetView];
    }else {
        targetView.tabAnimatedProduction = newProduction;
        [production.syncDelegateManager addDelegate:targetView];
    }
}

- (void)_productBackgroundLayerWithView:(UIView *)view needReset:(BOOL)needReset {
    
    UIView *flagView;
    BOOL isCard = NO;
    
    if ([view isKindOfClass:[UITableViewCell class]] || [view isKindOfClass:[UICollectionViewCell class]]) {
        if (view.subviews.count >= 1 && view.subviews[0].layer.shadowOpacity > 0.) {
            flagView = view.subviews[0];
            isCard = YES;
        }else if (view.subviews.count >= 2 && view.subviews[1].layer.shadowOpacity > 0.) {
            flagView = view.subviews[1];
            isCard = YES;
        }
    }else if (view.subviews.count >= 1 && view.subviews[0].layer.shadowOpacity > 0.) {
        flagView = view.subviews[0];
        isCard = YES;
    }
    
    if (flagView) {
        flagView.hidden = YES;
    }else {
        flagView = view;
    }
    
    view.tabAnimatedProduction.backgroundLayer = [TABAnimatedProductHelper getBackgroundLayerWithView:flagView controlView:self->_controlView];
    
    [self _productWithView:view needReset:needReset isCard:isCard];
}

- (void)_productWithView:(UIView *)view needReset:(BOOL)needReset isCard:(BOOL)isCard {

    [self.weakTargetViewArray addPointer:(__bridge void * _Nullable)(view)];
    [TABAnimatedProductHelper fullDataAndStartNestAnimation:view isHidden:!needReset rootView:view];
    view.hidden = YES;
    
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        
        __strong typeof(weakSelf) strongSelf = weakSelf;
        
        if (strongSelf.weakTargetViewArray.allObjects.count == 0) return;
        if (strongSelf.productIndex > strongSelf.weakTargetViewArray.allObjects.count-1) return;
        
        // 从等待队列中取出需要加工的view
        strongSelf->_targetView = [strongSelf.weakTargetViewArray pointerAtIndex:strongSelf.productIndex];
        if (!strongSelf->_targetView) return;
        
        strongSelf->_targetTagIndex = 0;
        // 生产流水
        [strongSelf _productWithTargetView:strongSelf->_targetView isCard:isCard];
        
        if (needReset) {
            [TABAnimatedProductHelper resetData:strongSelf->_targetView];
        }
        strongSelf.productIndex++;
        
    });
}

- (void)_productWithTargetView:(UIView *)targetView isCard:(BOOL)isCard {
    @autoreleasepool {
        if (!_controlView) return;
        TABAnimatedProduction *production = targetView.tabAnimatedProduction;
        NSString *controlerClassName = _controlView.tabAnimated.targetControllerClassName;
        production.fileName = [TABAnimatedProductHelper getKeyWithControllerName:controlerClassName targetClass:production.targetClass frame:_controlView.frame];
        
        NSMutableArray <TABComponentLayer *> *layerArray = @[].mutableCopy;
        // 生产
        [self _recurseProductLayerWithView:targetView array:layerArray production:production isCard:isCard];
        // 加工
        [self _chainAdjustWithArray:layerArray tabAnimated:_controlView.tabAnimated targetClass:production.targetClass];
        // 绑定
        production.state = TABAnimatedProductionBind;
        production.layers = layerArray;
        targetView.tabAnimatedProduction = production;
        // 缓存
        [[TABAnimatedCacheManager shareManager] cacheProduction:production];
    }
}

#pragma mark -

- (void)_recurseProductLayerWithView:(UIView *)view
                               array:(NSMutableArray <TABComponentLayer *> *)array
                          production:(TABAnimatedProduction *)production
                              isCard:(BOOL)isCard {
    [self _recurseProductLayerWithView:view array:array isCard:isCard];
}

- (void)_recurseProductLayerWithView:(UIView *)view
                               array:(NSMutableArray <TABComponentLayer *> *)array
                              isCard:(BOOL)isCard {
    
    NSArray *subViews;
    subViews = [view subviews];
    if ([subViews count] == 0) return;
    
    for (int i = 0; i < subViews.count;i++) {
        
        UIView *subV = subViews[i];
        if (subV.tabAnimated) continue;
        
        [self _recurseProductLayerWithView:subV array:array isCard:isCard];
        
        if ([self _cannotBeCreated:subV superView:view]) continue;
        
        // 标记移除：会生成动画对象，但是会被设置为移除状态
        BOOL needRemove = [self _isNeedRemove:subV];
        // 生产
        TABComponentLayer *layer;
        if ([TABAnimatedProductHelper canProduct:subV]) {
            UIColor *animatedColor = [_controlView.tabAnimated getCurrentAnimatedColorWithCollection:_controlView.traitCollection];
            layer = [self _createLayerWithView:subV needRemove:needRemove color:animatedColor isCard:isCard];
            layer.serializationImpl = _controlView.tabAnimated.serializationImpl;
            layer.tagIndex = self->_targetTagIndex;
            [array addObject:layer];
            _targetTagIndex++;
        }
    }
}

- (TABComponentLayer *)_createLayerWithView:(UIView *)view needRemove:(BOOL)needRemove color:(UIColor *)color isCard:(BOOL)isCard {
    
    TABComponentLayer *layer = TABComponentLayer.new;
    if (needRemove) {
        layer.loadStyle = TABViewLoadAnimationRemove;
        return layer;
    }
    
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *lab = (UILabel *)view;
        layer.numberOflines = lab.numberOfLines;
        if (lab.textAlignment == NSTextAlignmentCenter) {
            layer.origin = TABComponentLayerOriginCenterLabel;
            layer.contentsGravity = kCAGravityCenter;
        }else {
            layer.origin = TABComponentLayerOriginLabel;
        }
    }else {
        layer.numberOflines = 1;
        if ([view isKindOfClass:[UIImageView class]]) {
            layer.origin = TABComponentLayerOriginImageView;
        }else if([view isKindOfClass:[UIButton class]]) {
            layer.origin = TABComponentLayerOriginButton;
        }
    }
    
    // 坐标转换
    CGRect rect;
    if (isCard) {
        rect = view.frame;
    }else {
        rect = [_targetView convertRect:view.frame fromView:view.superview];
    }
    rect = [layer resetFrameWithRect:rect animatedHeight:_controlView.tabAnimated.animatedHeight];
    layer.frame = rect;
    
    if (layer.contents) {
        layer.backgroundColor = UIColor.clearColor.CGColor;
    }else if (layer.backgroundColor == nil) {
        layer.backgroundColor = color.CGColor;
    }
    
    CGFloat cornerRadius = view.layer.cornerRadius;
    if (cornerRadius == 0.) {
        if (_controlView.tabAnimated.cancelGlobalCornerRadius) {
            layer.cornerRadius = _controlView.tabAnimated.animatedCornerRadius;
        }else if ([TABAnimated sharedAnimated].useGlobalCornerRadius) {
            if ([TABAnimated sharedAnimated].animatedCornerRadius != 0.) {
                layer.cornerRadius = [TABAnimated sharedAnimated].animatedCornerRadius;
            }else {
                layer.cornerRadius = layer.frame.size.height/2.0;
            }
        }
    }else {
        layer.cornerRadius = cornerRadius;
    }
    
    return layer;
}

#pragma mark -

- (BOOL)_cannotBeCreated:(UIView *)view superView:(UIView *)superView {
    
    if ([view isKindOfClass:[NSClassFromString(@"UITableViewCellContentView") class]] ||
        [view isKindOfClass:[NSClassFromString(@"UICollectionViewCellContentView") class]]  ||
        [view isKindOfClass:[NSClassFromString(@"_UITableViewHeaderFooterViewBackground") class]]) {
        return YES;
    }
    
    // 移除UITableView/UICollectionView的滚动条
    if ([superView isKindOfClass:[UIScrollView class]]) {
        if (((view.frame.size.height < 3.) || (view.frame.size.width < 3.)) &&
            view.alpha == 0.) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)_isNeedRemove:(UIView *)view {
    
    BOOL needRemove = NO;
    // 分割线标记移除
    if ([view isKindOfClass:[NSClassFromString(@"_UITableViewCellSeparatorView") class]]  ||
        [view isKindOfClass:[NSClassFromString(@"_UITableViewHeaderFooterContentView") class]] ) {
        needRemove = YES;
    }
    
    // 通过过滤条件标记移除移除
    if (_controlView.tabAnimated.filterSubViewSize.width > 0) {
        if (view.frame.size.width <= _controlView.tabAnimated.filterSubViewSize.width) {
            needRemove = YES;
        }
    }
    
    if (_controlView.tabAnimated.filterSubViewSize.height > 0) {
        if (view.frame.size.height <= _controlView.tabAnimated.filterSubViewSize.height) {
            needRemove = YES;
        }
    }
    
    return needRemove;
}

- (void)_chainAdjustWithArray:(NSMutableArray <TABComponentLayer *> *)array
                  tabAnimated:(TABViewAnimated *)tabAnimated
                  targetClass:(Class)targetClass {
    if (tabAnimated.adjustBlock) {
        [self.chainManager chainAdjustWithArray:array adjustBlock:tabAnimated.adjustBlock];
    }
    if (tabAnimated.adjustWithClassBlock) {
        [self.chainManager chainAdjustWithArray:array adjustWithClassBlock:tabAnimated.adjustWithClassBlock targetClass:targetClass];
    }
}

- (void)_syncProduction:(TABAnimatedProduction *)production {
    @autoreleasepool {
        NSArray <UIView *> *array = [production.syncDelegateManager getDelegates];
        for (UIView *view in array) {
            TABAnimatedProduction *newProduction = view.tabAnimatedProduction;
            newProduction.backgroundLayer = production.backgroundLayer.copy;
            for (TABComponentLayer *layer in production.layers) {
                [newProduction.layers addObject:layer.copy];
            }
            [self _bindWithProduction:newProduction targetView:view];
        }
    }
}

- (void)_bindWithProduction:(TABAnimatedProduction *)production targetView:(UIView *)targetView {
    [TABAnimatedProductHelper bindView:targetView production:production animatedHeight:_controlView.tabAnimated.animatedHeight];
    [self.darkModeManager addNeedChangeView:targetView];
    [_animationManager addAnimationWithTargetView:targetView];
}

#pragma mark - Getter / Setter

- (void)setProductIndex:(NSInteger)productIndex {
    _productIndex = productIndex;
    if (productIndex >= self.weakTargetViewArray.allObjects.count) {
        self.productFinished = YES;
    }
}

- (void)setProductFinished:(BOOL)productFinished {
    _productFinished = productFinished;
    if (productFinished) {
        [self syncProductions];
    }
}

- (void)setControlView:(UIView *)controlView {
    _controlView = controlView;
    [_animationManager setControlView:controlView];
    if (_darkModeManager) {
        [_darkModeManager setControlView:controlView];
        [_darkModeManager addDarkModelSentryView];
    }
}

- (NSMutableDictionary *)productionPool {
    if (!_productionPool) {
        _productionPool = @{}.mutableCopy;
    }
    return _productionPool;
}

- (id <TABAnimatedChainManagerInterface>)chainManager {
    if (!_chainManager) {
        _chainManager = TABAnimatedChainManagerImpl.new;
    }
    return _chainManager;
}

@end
