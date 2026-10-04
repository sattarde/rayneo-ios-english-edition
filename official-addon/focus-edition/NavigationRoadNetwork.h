// NavigationRoadNetwork.h
// Even Realities G2-style OpenStreetMap Road Network Cache for RayNeo Smart Glasses.
// Fetches and caches local road segments (intersections, cross-streets, roundabouts)
// via Overpass API to render an intricate vector wireframe HUD.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface TIONavRoadNetwork : NSObject

+ (instancetype)sharedNetwork;

/// Request background update of surrounding road network around coordinate (within ~450m radius).
/// Automatically throttled: only fetches when moved >200m or >15 seconds since last query.
- (void)updateForCoordinate:(CLLocationCoordinate2D)coord;

/// Retrieve array of road segments currently cached near coordinate.
/// Each segment is an NSArray of @[ @(latitude), @(longitude) ] pairs.
- (NSArray<NSArray<NSArray<NSNumber *> *> *> *)segmentsNear:(CLLocationCoordinate2D)coord;

/// Clear cached network
- (void)clear;

@end
