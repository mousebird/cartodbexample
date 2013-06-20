//
//  GlobeViewController.m
//  CartoDBExample
//
//  Created by Steve Gifford on 6/13/13.
//  Copyright (c) 2013 mousebird consulting. All rights reserved.
//

#import "GlobeViewController.h"
#import "AFHTTPRequestOperation.h"
#import "AFJSONRequestOperation.h"

@interface GlobeViewController () <WhirlyGlobeViewControllerDelegate>

@end

@implementation GlobeViewController
{
    
    WhirlyGlobeViewController *globeViewC;
    // Whatever we're currently displaying
    NSMutableArray *displayedObjects;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
        displayedObjects = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Create an empty globe and tie it in to the view hierarchy
    globeViewC = [[WhirlyGlobeViewController alloc] init];
    globeViewC.delegate = self;
    [self.view addSubview:globeViewC.view];
    globeViewC.view.frame = self.view.bounds;
    [self addChildViewController:globeViewC];
    
    // We'll set up a cache directory for image tiles.
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)  objectAtIndex:0];
    NSString *thisCacheDir = [NSString stringWithFormat:@"%@/mbtilessat/",cacheDir];

    // This is a nice base layer with water and elevation, but no labels or boundaries
    MaplyQuadEarthWithRemoteTiles *layer = [[MaplyQuadEarthWithRemoteTiles alloc] initWithBaseURL:@"http://a.tiles.mapbox.com/v3/mousebird.map-2ebn78d1/" ext:@"png" minZoom:0 maxZoom:8];
    layer.handleEdges = YES;
    layer.cacheDir = thisCacheDir;
    [globeViewC addLayer:layer];

    // Let's start up over San Francisco, center of the universe
    [globeViewC animateToPosition:MaplyCoordinateMakeWithDegrees(-122.4192, 37.7793) time:1.0];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// Clean out whatever we're currently displaying
- (void)clearDisplay
{
    @synchronized(displayedObjects)
    {
        if ([displayedObjects count])
        {
            [globeViewC removeObjects:displayedObjects];
            [displayedObjects removeAllObjects];
        }
    }
}

// Add an admin0 (country, basically) outline and label
- (void)addCountry:(MaplyVectorObject *)vecs
{
    if (!vecs)
        return;
    
    NSMutableArray *compObjs = [NSMutableArray array];
    
    // Add the the vectors to the globe with a line width a color and other parameters
    MaplyComponentObject *vecCompObj = [globeViewC addVectors:@[vecs] desc:
                                        @{kMaplyColor: [UIColor whiteColor],kMaplyVecWidth: @(5.0),kMaplyDrawOffset: @(0),kMaplyDrawPriority:@(20),kMaplyFade: @(1.0)}];
    if (vecCompObj)
        [compObjs addObject:vecCompObj];
    // But hey, what about a label?  Let's figure out where it should go.
    MaplyCoordinate center = [vecs center];
    NSString *name = vecs.attributes[@"sovereignt"];
    if (name)
    {
        // We'll create a 2D (screen) label at that point and the layout engine will control it
        MaplyScreenLabel *admin0Label = [[MaplyScreenLabel alloc] init];
        admin0Label.text = name;
        admin0Label.loc = center;
        admin0Label.selectable = NO;
        admin0Label.layoutImportance = 2.0;
        MaplyComponentObject *labelCompObj = [globeViewC addScreenLabels:@[admin0Label] desc:
                                              @{kMaplyColor: [UIColor whiteColor],kMaplyFont: [UIFont boldSystemFontOfSize:20.0],kMaplyShadowColor: [UIColor blackColor], kMaplyShadowSize: @(1.0), kMaplyFade: @(1.0)}];
        [compObjs addObject:labelCompObj];
    }

    // Keep track of what we've added
    @synchronized(displayedObjects)
    {
        [displayedObjects addObjectsFromArray:compObjs];
    }
}

// Add the regions behind the countries
- (void)addRegions:(MaplyVectorObject *)vecs
{
    if (!vecs)
        return;

    NSMutableArray *compObjs = [NSMutableArray array];

    // Add the the vectors to the globe with a line width a color and other parameters
    MaplyComponentObject *vecCompObj = [globeViewC addVectors:@[vecs] desc:
                                        @{kMaplyColor: [UIColor brownColor],kMaplyVecWidth: @(2.0),kMaplyDrawOffset: @(0),kMaplyDrawPriority:@(10), kMaplyFade: @(1.0)}];
    if (vecCompObj)
        [compObjs addObject:vecCompObj];
    
    // Keep track of what we've added
    @synchronized(displayedObjects)
    {
        [displayedObjects addObjectsFromArray:compObjs];
    }
}

// Request the admin1 data for a given admin0 region
- (void)requestRegionsFor:(NSString *)adm0_a3
{
    // We want the geometry for everything that matches the adm0_a3 designator from the admin0 table
    NSString *queryStr = [NSString stringWithFormat:
                          @"http://%@.cartodb.com/api/v2/sql?format=GeoJSON&q=\
                          SELECT name_1,the_geom FROM %@ \
                          WHERE adm0_a3 = '%@'",
                          account,admin1Table,adm0_a3];

    // Kick off the request
    NSURLRequest *request = [NSURLRequest requestWithURL:
                             [NSURL URLWithString:[queryStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    AFJSONRequestOperation *operation =
    [AFJSONRequestOperation JSONRequestOperationWithRequest:request
                                                    success:
     // We'll do this if we succeed
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
     {
         // Let's do the parsing and such on another queue.  No reason to clog up the main thread.
         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                        ^{
                            MaplyVectorObject *regionsVec = [MaplyVectorObject VectorObjectFromGeoJSONDictionary:(NSDictionary *) JSON];
                            if (regionsVec)
                            {
                                // Convert to GeoJSON and add the region outlines
                                [self addRegions:regionsVec];
                            }
                        });
     }
                                                    failure:
     // And nothing if we fail
     ^(NSURLRequest *request, NSHTTPURLResponse *response,NSError *error, id JSON)
     {
     }
     ];
    
    // Kick off the network request
    [operation start];
}

#pragma mark - WhirlyGlobeViewController Delegate

static NSString *account = @"mousebird";
static NSString *admin0Table = @"table_10m_admin_0_map_subunits";
static NSString *admin1Table = @"table_10m_admin_1_states_provinces_shp";

- (void)globeViewController:(WhirlyGlobeViewController *)viewC didTapAt:(WGCoordinate)coord
{
    // We need degrees for the query, even if we work in radians internally
    float lat = coord.y * 180.0 / M_PI;
    float lon = coord.x * 180.0 / M_PI;

    // We want the geometry and a couple of attributes for just one feature under the point
    NSString *queryStr = [NSString stringWithFormat:
            @"http://%@.cartodb.com/api/v2/sql?format=GeoJSON&q=\
                          SELECT sovereignt,adm0_a3,the_geom FROM %@ \
                          WHERE ST_Intersects(the_geom,ST_SetSRID(ST_Point(%f,%f),4326)) \
                          LIMIT 1",account,admin0Table,lon,lat];

    // Kick off the request with AFNetworking.  We can deal with the result in a block
    NSURLRequest *request = [NSURLRequest requestWithURL:
                             [NSURL URLWithString:[queryStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    AFJSONRequestOperation *operation =
    [AFJSONRequestOperation JSONRequestOperationWithRequest:request
            success:
     // We'll do this if we succeed
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON)
     {
         // Get rid of everything we're currently displaying
         [self clearDisplay];
         
         // Let's do the parsing and such on another queue.  No reason to clog up the main thread.
         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                        ^{
                            MaplyVectorObject *countryVec = [MaplyVectorObject VectorObjectFromGeoJSONDictionary:(NSDictionary *) JSON];
                            if (countryVec)
                            {
                                // Convert to GeoJSON and add the country outline
                                [self addCountry:countryVec];

                                // And let's kick of a request for the admin1 regions
                                [self requestRegionsFor:countryVec.attributes[@"adm0_a3"]];
                            }
                        });
     }
            failure:
     // And nothing if we fail
     ^(NSURLRequest *request, NSHTTPURLResponse *response,NSError *error, id JSON)
     {
     }
     ];
    
    // Kick off the network request
    [operation start];
}

@end
