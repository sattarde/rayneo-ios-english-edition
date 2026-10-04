// NavigationRoadNetwork.inc
// Implementation of OpenStreetMap Road Network Cache for Even Realities-style HUD.

#import "NavigationRoadNetwork.h"

@interface TIONavRoadNetwork ()
@property (nonatomic, assign) CLLocationCoordinate2D lastCenter;
@property (nonatomic, assign) NSTimeInterval lastFetchTime;
@property (nonatomic, assign) BOOL fetching;
@property (nonatomic, strong) NSArray<NSArray<NSArray<NSNumber *> *> *> *cachedSegments;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@end

@implementation TIONavRoadNetwork

+ (instancetype)sharedNetwork {
    static TIONavRoadNetwork *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[self alloc] init];
    });
    return s_instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lastCenter = CLLocationCoordinate2DMake(0, 0);
        _lastFetchTime = 0;
        _fetching = NO;
        _cachedSegments = @[];
        _workQueue = dispatch_queue_create("com.rayneo.nav.roadnetwork", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)clear {
    @synchronized (self) {
        _cachedSegments = @[];
        _lastCenter = CLLocationCoordinate2DMake(0, 0);
        _lastFetchTime = 0;
        _fetching = NO;
    }
}

- (void)updateForCoordinate:(CLLocationCoordinate2D)coord {
    if (!CLLocationCoordinate2DIsValid(coord) || (coord.latitude == 0 && coord.longitude == 0)) return;
    
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    @synchronized (self) {
        if (_fetching) return;
        if (_cachedSegments.count > 0 && now - _lastFetchTime < 15.0) {
            // Check distance
            CLLocation *loc1 = [[CLLocation alloc] initWithLatitude:_lastCenter.latitude longitude:_lastCenter.longitude];
            CLLocation *loc2 = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
            if ([loc1 distanceFromLocation:loc2] < 200.0) {
                return; // still within current tile radius
            }
        }
        _fetching = YES;
    }
    
    dispatch_async(_workQueue, ^{
        // 450m bounding box around coord
        double radiusMeters = 450.0;
        double dLat = radiusMeters / 111320.0;
        double cosLat = cos(coord.latitude * M_PI / 180.0);
        if (fabs(cosLat) < 0.01) cosLat = 0.01;
        double dLon = radiusMeters / (111320.0 * cosLat);
        
        double south = coord.latitude - dLat;
        double north = coord.latitude + dLat;
        double west  = coord.longitude - dLon;
        double east  = coord.longitude + dLon;
        
        // Exclude non-navigable paths to keep vector complexity crisp and high-speed
        NSString *query = [NSString stringWithFormat:
            @"[out:json][timeout:6];way[\"highway\"][\"highway\"!~\"footway|cycleway|path|steps|service|track|corridor|elevator|platform\"](%.6f,%.6f,%.6f,%.6f);out geom;",
            south, west, north, east];
        
        NSString *urlStr = [NSString stringWithFormat:@"https://overpass-api.de/api/interpreter?data=%@",
                            [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
        
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url) {
            @synchronized (self) { self.fetching = NO; }
            return;
        }
        
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:7.0];
        [req setValue:@"RayNeo-G2-HUD/1.0" forHTTPHeaderField:@"User-Agent"];
        
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
            if (!err && data.length > 0) {
                NSError *jsonErr = nil;
                NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
                if (!jsonErr && [root isKindOfClass:[NSDictionary class]]) {
                    NSArray *elements = root[@"elements"];
                    if ([elements isKindOfClass:[NSArray class]]) {
                        NSMutableArray *parsed = [NSMutableArray arrayWithCapacity:elements.count];
                        for (NSDictionary *elem in elements) {
                            NSArray *geom = elem[@"geometry"];
                            if ([geom isKindOfClass:[NSArray class]] && geom.count >= 2) {
                                NSMutableArray *line = [NSMutableArray arrayWithCapacity:geom.count];
                                for (NSDictionary *pt in geom) {
                                    NSNumber *lat = pt[@"lat"];
                                    NSNumber *lon = pt[@"lon"];
                                    if (lat && lon) {
                                        [line addObject:@[lat, lon]];
                                    }
                                }
                                if (line.count >= 2) {
                                    [parsed addObject:line];
                                }
                            }
                        }
                        
                        @synchronized (self) {
                            self.cachedSegments = [parsed copy];
                            self.lastCenter = coord;
                            self.lastFetchTime = NSProcessInfo.processInfo.systemUptime;
                            self.fetching = NO;
                        }
                        return;
                    }
                }
            }
            @synchronized (self) {
                self.fetching = NO;
            }
        }];
        [task resume];
    });
}

- (NSArray<NSArray<NSArray<NSNumber *> *> *> *)segmentsNear:(CLLocationCoordinate2D)coord {
    @synchronized (self) {
        return _cachedSegments ?: @[];
    }
}

@end
