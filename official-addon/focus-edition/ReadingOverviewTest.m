#import "ReadingOverview.h"
#include <assert.h>
#include <stdio.h>
int main(void) { @autoreleasepool {
    assert([TWReadingDuration(@3661) isEqual:@"1 hour 1 minute"]);
    assert([TWReadingDuration(@59) isEqual:@"Less than 1 min"]);
    assert([TWReadingDuration(nil) isEqual:@"No Data"]);
    assert([TWReadingDuration(@YES) isEqual:@"No Data"]);
    assert([TWReadingDuration(@(-1)) isEqual:@"No Data"]);
    assert(TWReadingStatsRequest(@"overall") != nil);
    assert(TWReadingStatsRequest(@"arbitrary") == nil);
    NSMutableArray *hours = [NSMutableArray new];
    for (int i=0;i<24;i++) [hours addObject:@(i)];
    NSDictionary *r=TWReadingOverview(@{@"totalReadTime":@3661, @"readDays":@2,
      @"readTimes":@{@"0":@999999}, @"dayAverageReadTime":@120,
      @"preferCategory":@[@{@"categoryTitle":@"literature", @"readingTime":@3600, @"val":@1},
                           @{@"categoryTitle":@"Default placeholder", @"readingTime":@0, @"val":@1}, NSNull.null],
      @"readStat":@[@{@"stat":@"Finished", @"counts":@"2 books"}, @{@"stat":@"Notes", @"counts":@"4 items"}],
      @"preferTime":hours}, @"monthly");
    assert([r[@"duration"] isEqual:@"1 hour 1 minute"]);
    assert([r[@"dayAverage"] isEqual:@"0 hours 2 minutes"]);
    assert([r[@"categories"] count]==1 && [r[@"depthEvidence"] count]==2);
    assert([r[@"hourly"][0][@"hour"] intValue]==6);
    assert([r[@"hourly"][18][@"hour"] intValue]==0);
    assert(r[@"depthScore"] == nil && r[@"completionRate"] == nil);
    NSDictionary *missing=TWReadingOverview(@{@"readTimes":@{@"0":@9000}, @"readDays":@1.5}, @"overall");
    assert(missing[@"totalSeconds"]==NSNull.null && missing[@"readDays"]==NSNull.null);
    assert([TWReadingOverview((id)NSNull.null,@"overall") count]==0);
    assert([TWReadingOverview(@{},@"invalid") count]==0);
    puts("PASS reading overview: units, missing values, placeholders, 06:00 buckets, no invented depth score");
} return 0; }
