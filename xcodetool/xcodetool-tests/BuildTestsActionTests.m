
#import <SenTestingKit/SenTestingKit.h>
#import "Action.h"
#import "xcodeSubjectInfo.h"
#import "RunTestsAction.h"
#import "ImplicitAction.h"
#import "Fakes.h"
#import "Functions.h"
#import "TestUtil.h"

@interface BuildTestsActionTests : SenTestCase
@end

@implementation BuildTestsActionTests

- (void)setUp
{
  [super setUp];
  SetTaskInstanceBlock(nil);
  ReturnFakeTasks(nil);
}

- (void)testOnlyListIsCollected
{
  // The subject being the workspace/scheme or project/target we're testing.
  ReturnFakeTasks(@[
                  [FakeTask fakeTaskWithExitStatus:0
                                standardOutputPath:TEST_DATA @"TestProject-Library-TestProject-Library-showBuildSettings.txt"
                                 standardErrorPath:nil]
                  ]);
  
  ImplicitAction *options = [TestUtil validatedOptionsFromArgumentList:@[
                      @"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
                      @"-scheme", @"TestProject-Library",
                      @"-sdk", @"iphonesimulator6.1",
                      @"build-tests", @"-only", @"TestProject-LibraryTests",
                      ]];
  RunTestsAction *action = options.actions[0];
  assertThat((action.onlyList), equalTo(@[@"TestProject-LibraryTests"]));
}

- (void)testOnlyListRequiresValidTarget
{
  // The subject being the workspace/scheme or project/target we're testing.
  ReturnFakeTasks(@[
                  [FakeTask fakeTaskWithExitStatus:0
                                standardOutputPath:TEST_DATA @"TestProject-Library-TestProject-Library-showBuildSettings.txt"
                                 standardErrorPath:nil]
                  ]);
  
  [TestUtil assertThatOptionsValidationWithArgumentList:@[
   @"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
   @"-scheme", @"TestProject-Library",
   @"-sdk", @"iphonesimulator6.1",
   @"build-tests", @"-only", @"BOGUS_TARGET",
   ]
                                       failsWithMessage:@"build-tests: 'BOGUS_TARGET' is not a testing target in this scheme."];
}

- (void)testBuildTestsAction
{
  XcodeTool *tool = [[[XcodeTool alloc] init] autorelease];
  
  tool.arguments = @[@"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
                     @"-scheme", @"TestProject-Library",
                     @"-configuration", @"Debug",
                     @"-sdk", @"iphonesimulator6.0",
                     @"build-tests"];
  
  // We'll expect to see one call to xcodebuild with -showBuildSettings - we have to fetch the OBJROOT
  // and SYMROOT variables so we can build the tests in the correct location.
  NSTask *task1 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestProject-Library-showBuildSettings.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task1ExpectedArguments = @[
                                      @"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
                                      @"-scheme", @"TestProject-Library",
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-showBuildSettings"
                                      ];
  
  
  // We'll expect to see another xcodebuild call to build the test target.
  NSTask *task2 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestProject-Library-TestProject-LibraryTests-build.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task2ExpectedArguments = @[
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
                                      @"-target", @"TestProject-Library",
                                      @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestProject-Library-amxcwsnetnrvhrdeikqmcczcgmwn/Build/Intermediates",
                                      @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestProject-Library-amxcwsnetnrvhrdeikqmcczcgmwn/Build/Products",
                                      @"build",
                                      ];

  // We'll expect to see another xcodebuild call to build the test target.
  NSTask *task3 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestProject-Library-TestProject-LibraryTests-build.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task3ExpectedArguments = @[
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-project", TEST_DATA @"TestProject-Library/TestProject-Library.xcodeproj",
                                      @"-target", @"TestProject-LibraryTests",
                                      @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestProject-Library-amxcwsnetnrvhrdeikqmcczcgmwn/Build/Intermediates",
                                      @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestProject-Library-amxcwsnetnrvhrdeikqmcczcgmwn/Build/Products",
                                      @"build",
                                      ];
  
  NSArray *sequenceOfTasks = @[task1, task2, task3];
  __block NSUInteger sequenceOffset = 0;
  
  SetTaskInstanceBlock(^(void){
    return [sequenceOfTasks objectAtIndex:sequenceOffset++];
  });
  
  [TestUtil runWithFakeStreams:tool];
  
  assertThat(task1.arguments, equalTo(task1ExpectedArguments));
  assertThat(task2.arguments, equalTo(task2ExpectedArguments));
  assertThat(task3.arguments, equalTo(task3ExpectedArguments));
  assertThatInt(tool.exitStatus, equalToInt(0));
}

- (void)testBuildTestsActionWillBuildEverythingMarkedAsBuildForTest
{
  // In TestWorkspace-Library, we have a target TestProject-LibraryTest2 that depends on
  // TestProject-OtherLib, but it isn't marked as an explicit dependency.  The only way that
  // dependency gets built is that it's added to the scheme as build-for-test above
  // TestProject-LibraryTest2.  This a lame way to setup dependencies (they should be explicit),
  // but we're seeing this in the wild and should support it.
  XcodeTool *tool = [[[XcodeTool alloc] init] autorelease];
  
  tool.arguments = @[@"-workspace", TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace",
                     @"-scheme", @"TestProject-Library",
                     @"-configuration", @"Debug",
                     @"-sdk", @"iphonesimulator6.0",
                     @"build-tests"];
  
  // We'll expect to see one call to xcodebuild with -showBuildSettings - we have to fetch the OBJROOT
  // and SYMROOT variables so we can build the tests in the correct location.
  NSTask *task1 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestWorkspace-Library-TestProject-Library-showBuildSettings.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task1ExpectedArguments = @[
                                      @"-workspace", TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace",
                                      @"-scheme", @"TestProject-Library",
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-showBuildSettings"
                                      ];
  
  // We'll expect to see another xcodebuild call to build the TestProject-LibraryTests
  NSTask *task2 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestWorkspace-Library-TestProject-LibraryTests-build.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task2ExpectedArguments = @[
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-project", TEST_DATA @"TestWorkspace-Library/TestProject-Library/TestProject-Library.xcodeproj",
                                      @"-target", @"TestProject-Library",
                                      @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates",
                                      @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Products",
                                      @"build",
                                      ];

  NSTask *task3 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestWorkspace-Library-TestProject-LibraryTests-build.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task3ExpectedArguments = @[
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-project", TEST_DATA @"TestWorkspace-Library/TestProject-Library/TestProject-Library.xcodeproj",
                                      @"-target", @"TestProject-OtherLib",
                                      @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates",
                                      @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Products",
                                      @"build",
                                      ];
  
  // We'll expect to see another xcodebuild call to build the TestProject-LibraryTests2
  NSTask *task4 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestWorkspace-Library-TestProject-LibraryTests-build.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task4ExpectedArguments = @[
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-project", TEST_DATA @"TestWorkspace-Library/TestProject-Library/TestProject-Library.xcodeproj",
                                      @"-target", @"TestProject-LibraryTests",
                                      @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates",
                                      @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Products",
                                      @"build",
                                      ];
  
  // We'll expect to see another xcodebuild call to build the TestProject-LibraryTests2
  NSTask *task5 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestWorkspace-Library-TestProject-LibraryTests-build.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task5ExpectedArguments = @[
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-project", TEST_DATA @"TestWorkspace-Library/TestProject-Library/TestProject-Library.xcodeproj",
                                      @"-target", @"TestProject-LibraryTests2",
                                      @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates",
                                      @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Products",
                                      @"build",
                                      ];
  
  NSArray *sequenceOfTasks = @[task1, task2, task3, task4, task5];
  __block NSUInteger sequenceOffset = 0;
  
  SetTaskInstanceBlock(^(void){
    return [sequenceOfTasks objectAtIndex:sequenceOffset++];
  });
  
  [TestUtil runWithFakeStreams:tool];
  
  assertThat(task1.arguments, equalTo(task1ExpectedArguments));
  assertThat(task2.arguments, equalTo(task2ExpectedArguments));
  assertThat(task3.arguments, equalTo(task3ExpectedArguments));
  assertThat(task4.arguments, equalTo(task4ExpectedArguments));
  assertThat(task5.arguments, equalTo(task5ExpectedArguments));
  assertThatInt(tool.exitStatus, equalToInt(0));
}

- (void)testBuildTestsCanBuildASingleTarget
{
  // In TestWorkspace-Library, we have a target TestProject-LibraryTest2 that depends on
  // TestProject-OtherLib, but it isn't marked as an explicit dependency.  The only way that
  // dependency gets built is that it's added to the scheme as build-for-test above
  // TestProject-LibraryTest2.  This a lame way to setup dependencies (they should be explicit),
  // but we're seeing this in the wild and should support it.
  XcodeTool *tool = [[[XcodeTool alloc] init] autorelease];
  
  tool.arguments = @[@"-workspace", TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace",
                     @"-scheme", @"TestProject-Library",
                     @"-configuration", @"Debug",
                     @"-sdk", @"iphonesimulator6.0",
                     @"build-tests", @"-only", @"TestProject-LibraryTests"];
  
  // We'll expect to see one call to xcodebuild with -showBuildSettings - we have to fetch the OBJROOT
  // and SYMROOT variables so we can build the tests in the correct location.
  NSTask *task1 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestWorkspace-Library-TestProject-Library-showBuildSettings.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task1ExpectedArguments = @[
                                      @"-workspace", TEST_DATA @"TestWorkspace-Library/TestWorkspace-Library.xcworkspace",
                                      @"-scheme", @"TestProject-Library",
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-showBuildSettings"
                                      ];
  
  // We'll expect to see another xcodebuild call to build the TestProject-LibraryTests
  NSTask *task2 = [TestUtil fakeTaskWithExitStatus:0
                                    standardOutput:[NSString stringWithContentsOfFile:TEST_DATA @"TestWorkspace-Library-TestProject-LibraryTests-build.txt" encoding:NSUTF8StringEncoding error:nil]
                                     standardError:nil];
  NSArray *task2ExpectedArguments = @[
                                      @"-configuration", @"Debug",
                                      @"-sdk", @"iphonesimulator6.0",
                                      @"-project", TEST_DATA @"TestWorkspace-Library/TestProject-Library/TestProject-Library.xcodeproj",
                                      @"-target", @"TestProject-LibraryTests",
                                      @"OBJROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Intermediates",
                                      @"SYMROOT=/Users/fpotter/Library/Developer/Xcode/DerivedData/TestWorkspace-Library-gjpyghvhqizojqckzrwwumrsqgoo/Build/Products",
                                      @"build",
                                      ];
  
  NSArray *sequenceOfTasks = @[task1, task2];
  __block NSUInteger sequenceOffset = 0;
  
  SetTaskInstanceBlock(^(void){
    return [sequenceOfTasks objectAtIndex:sequenceOffset++];
  });
  
  [TestUtil runWithFakeStreams:tool];
  
  assertThat(task1.arguments, equalTo(task1ExpectedArguments));
  assertThat(task2.arguments, equalTo(task2ExpectedArguments));
  assertThatInt(tool.exitStatus, equalToInt(0));
}

@end
