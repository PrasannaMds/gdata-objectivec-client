/* Copyright (c) 2007 Google Inc.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

//
//  GDataElementsTest.m
//

// Unit tests for the Objective-C GData framework element classes

#import "GData.h"
#import "GDataElementsTest.h"

#define typeof __typeof__ // fixes http://www.brethorsting.com/blog/2006/02/stupid_issue_with_ocunit.html

@implementation GDataElementsTest

- (NSString *)entryNamespaceString {
  NSString * const kNamespaceString = @"xmlns='http://www.w3.org/2005/Atom'"
                        " xmlns:gd='http://schemas.google.com/g/2005' "
                        " xmlns:gm='http://base.google.com/ns-metada/1.0' "
                        " xmlns:g='http://base.google.com/ns/1.0' "
                        " xmlns:gCal='http://schemas.google.com/gCal/2005' "
                        " xmlns:gs='http://schemas.google.com/spreadsheets/2006' "
                        " xmlns:gsx='http://schemas.google.com/spreadsheets/2006/extended' "
                        " xmlns:batch='http://schemas.google.com/gdata/batch' "
                        " xmlns:app='http://purl.org/atom/app#'"
                        " xmlns:media='http://search.yahoo.com/mrss/'" 
                        " xmlns:gphoto='http://schemas.google.com/photos/2007'"
                        " xmlns:exif='http://schemas.google.com/photos/exif/2007'"
                        " xmlns:geo='http://www.w3.org/2003/01/geo/wgs84_pos#'"
                        " xmlns:georss='http://www.georss.org/georss'"
                        " xmlns:gml='http://www.opengis.net/gml' ";
  
  return kNamespaceString;
}

// Allocate a GDataObject of a known class, initialized from the 
// given XML.
//
// For XML needing but lacking namespace information, it will
// be allocated by being temporarily wrapped in a parent which
// has the full set of GData namespaces.
- (GDataObject *)GDataObjectForClassName:(Class)gdataClass
                               XMLString:(NSString *)xmlString
         shouldWrapWithNamespaceAndEntry:(BOOL)shouldWrap {
  
  
  NSString *wrappedXMLString = xmlString;
  
  if (shouldWrap) {
    // make an outer element with the namespace
    NSString * const kNamespaceWrapperString = @"<entry %@ >%@</entry>";
    
    wrappedXMLString = [NSString stringWithFormat:
      kNamespaceWrapperString,
      [self entryNamespaceString], xmlString];
  }
  
  // make an XML element for the wrapped XML, then extract the inner element
  NSError *error = nil;
  NSXMLElement *entryXML = [[[NSXMLElement alloc] initWithXMLString:wrappedXMLString
                                                              error:&error] autorelease];
  STAssertNil(error, @"%@", error);
  
  NSXMLElement *element = (NSXMLElement *) [entryXML childAtIndex:0];
  STAssertNotNil(element, @"Cannot get child of %@", entryXML);
  
  // allocate our GData object from the inner element
  GDataObject *obj = [[[gdataClass alloc] initWithXMLElement:element
                                                      parent:nil] autorelease];
  return obj;
}

// This is the same as Obj-C's as valueForKeyPath: but allows array indices
// as path elements, like foo.0.bar
+ (id)valueInObject:(id)obj
  forKeyPathIncludingArrays:(NSString *)keyPath {
  
  NSArray *pathList = [keyPath componentsSeparatedByString:@"."];
  NSMutableArray *partialKeyPathList = [NSMutableArray array];

  // step through keys in the path
  id targetObj = obj;
  for (int idx = 0; idx < [pathList count]; idx++) {
    
    // if a key is an integer or "@count", then evaluate the array or set
    // preceding it and extract the object indexed by the integer or the count
    // of array objects
    id thisKey = [pathList objectAtIndex:idx];
    if ([thisKey isEqual:@"@count"]
        || [thisKey isEqual:@"0"] 
        || [thisKey intValue] > 0) {
      
      NSString *partialPathString = [partialKeyPathList componentsJoinedByString:@"."];
      
      NSArray *targetArray = [targetObj valueForKeyPath:partialPathString];
      
      [partialKeyPathList removeAllObjects];

      if ([thisKey isEqual:@"@count"]) {
        targetObj = [NSNumber numberWithInt:[targetArray count]];
      } else {
        int arrayIndex = [thisKey intValue];
        targetObj = [targetArray objectAtIndex:arrayIndex];
      }
    } else {
      // for non-integer keys, just keep accumulating keys in the path
      [partialKeyPathList addObject:thisKey];
    }
  }
  if ([partialKeyPathList count]) {
    // find the final target object given the accumulated keys in the path
    NSString *finalKeyPathString = [partialKeyPathList componentsJoinedByString:@"."];
    
    @try {
      targetObj = [targetObj valueForKeyPath:finalKeyPathString];
    } 
    @catch(NSException *exc) {
      NSLog(@"testing class:%@ keyPath:\"%@\"", [obj class], keyPath);
      @throw;
    }
  }
  return targetObj;
}

// runElementTests: takes an array of ElementTestKeyPathValues, where the
// first is (class, xml) and later ones are (test path, expected value)
// 
// Empty strings mark end-of-element, nils mark end-of-test-array
//
// We'll test each element this way:
//
// 1. Generate the NSXMLElement from an XML string (wrapped by an outer <entry> 
//    element with the namespace)
// 2. Extract the inner element we care about
// 3. Create a GData object for the element (obj1)
// 4. Copy the GData object (obj1copy)
// 5. Generate an XML element from the copy (outputXML)
// 6. Create a new GData object from the output XML (obj2)
// 7. Test that [obj2 isEqual:obj1copy]
// 8. Run a series of key-value coding tests on obj2 to be sure it contains
//    everything we expect.
// 9. If the tests did not include checks for unknown elements or
//    attributes, then those are tested to be sure they are 0.

- (void)runElementTests:(ElementTestKeyPathValues *)tests {

  for (int testIndex = 0;
       tests[testIndex].str1 != nil;
       testIndex++) {
    
    // get the GData class and the XML string from the table
    NSString *className = tests[testIndex].str1;
    NSString *testXMLString = tests[testIndex].str2;
    
    Class gdataClass = NSClassFromString(className);
    STAssertNotNil(gdataClass, @"Cannot make class for class name: %@", className);
    
    // make a GDataObject instance with the XML
    GDataObject *obj1 = [self GDataObjectForClassName:gdataClass
                                            XMLString:testXMLString
                      shouldWrapWithNamespaceAndEntry:YES];
    
    // make a copy of the object, and verify that it equals the original 
    GDataObject *obj1copy = [[obj1 copy] autorelease];
    STAssertTrue([obj1 isEqual:obj1copy], @"Failed copy from %@ to %@",
                 obj1, obj1copy);
    
    // get XML from the copy, make a new instance from the XML, and verify
    // the the new instance equals the previous copy
    NSXMLElement *outputXML = [obj1copy XMLElement];
    
    GDataObject *obj2 = [[[gdataClass alloc] initWithXMLElement:outputXML
                                                         parent:nil] autorelease];
    STAssertTrue([obj2 isEqual:obj1copy], @"Failed using XML to convert\n  %@\nas XML:\n  %@\nto\n  %@",  
                 obj1copy, outputXML, obj2);
    
    // step through each test for this element, evaluate the key-value path,
    // and compare the result to the expected value string
    //
    // also, track if tests of unknownChildren or unknownAttributes are 
    // performed
    BOOL testedForUnknownChildren = NO;
    BOOL testedForUnknownAttributes = NO;
    
    while (1) {
      
      ++testIndex;
      
      NSString *keyPath = tests[testIndex].str1;
      NSString *expectedValue = tests[testIndex].str2;
      
      if (keyPath == nil || [keyPath length] == 0) break;
      
      NSString *result = [GDataElementsTest valueInObject:obj2 forKeyPathIncludingArrays:keyPath];
      
      STAssertTrue(AreEqualOrBothNil(result, expectedValue), 
                   @"failed %@ testing key path %@:\n %@ \n!= \n %@", 
                   obj2, keyPath, result, expectedValue);
      
      if ([keyPath hasPrefix:@"unknownChildren"]) testedForUnknownChildren = YES;
      if ([keyPath hasPrefix:@"unknownAttributes"]) testedForUnknownAttributes = YES;
    }
    
    // if there were no explicit tests on this test object for unknown children
    // or attributes, then verify now that there are in fact no unknown children
    // or attributes present in the object
    
    if (!testedForUnknownChildren) {
      NSString *keyPath = @"unknownChildren.@count.stringValue";
      NSString *expectedValue = @"0";
      NSString *result = [GDataElementsTest valueInObject:obj2 
                                forKeyPathIncludingArrays:keyPath];
      
      // this object should have no unparsed children
      STAssertTrue(AreEqualOrBothNil(result, expectedValue),
                   @"failed %@ testing:\n %@ \n!= \n %@\n unknown children: %@", 
                   obj2, result, expectedValue, 
                   [GDataElementsTest valueInObject:obj2 
                          forKeyPathIncludingArrays:@"unknownChildren"]);      
    }
    
    if (!testedForUnknownAttributes) {
      NSString *keyPath = @"unknownAttributes.@count.stringValue";
      NSString *expectedValue = @"0";
      NSString *result = [GDataElementsTest valueInObject:obj2 
                                forKeyPathIncludingArrays:keyPath];
      
      // this object should have no unparsed attributes
      STAssertTrue(AreEqualOrBothNil(result, expectedValue),
                   @"failed %@ testing:\n %@ \n!= \n %@", 
                   obj2, result, expectedValue,
                   [GDataElementsTest valueInObject:obj2 
                          forKeyPathIncludingArrays:@"unknownAttributes"]);      
    }
  }
}



- (void)testElements {
  
  // this method tests base elements, using runElementTests: above
  
  // The tests mostly include static strings, but we'll generate a few 
  // strings dynamically first.
  
  // Test a non-ASCII character and some html characters in a TextConstruct.  
  // We'll allocate it dynamically since source code cannot contain non-ASCII.
  NSString *template = @"Test ellipse (%C) and others \"<&>";
  NSString *textConstructTestResult = [NSString stringWithFormat:template, 8230];
  
  // To test an inline feed, we'll read in the cells feed test file,
  // strip the <?xml...> prefix, and wrap it in a gd:feedLink
  NSString *inlineFeed = [NSString stringWithContentsOfFile:@"Tests/FeedSpreadsheetCellsTest1.xml"];
  inlineFeed = [inlineFeed substringFromIndex:[@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>" length]];
  NSString *inlinedFeedLinkStr = [NSString stringWithFormat:@"<gd:feedLink>%@</gd:feedLink>", inlineFeed];
  
  ElementTestKeyPathValues tests[] =
  { 
    { @"GDataCategory", @"<category scheme=\"http://schemas.google.com/g/2005#kind\" "
      "term=\"http://schemas.google.com/g/2005#event\" label=\"My Category\" "
      "xml:lang=\"myLanguage\" unkAttr=\"ABCDE\" unkAttr2=\"EFGHI\" />" },
    { @"scheme", kGDataCategoryScheme },
    { @"term", kGDataCategoryEvent },
    { @"label", @"My Category" },
    { @"labelLang", @"myLanguage" },
    { @"unknownAttributes.0.XMLString", @"unkAttr=\"ABCDE\"" },
    { @"unknownAttributes.1.XMLString", @"unkAttr2=\"EFGHI\"" },
    { @"unknownAttributes.@count.stringValue", @"2" },
    { @"", @"" },
      
    { @"GDataComment", @"<gd:comments rel=\"http://schemas.google.com/g/2005#reviews\"> "
      "<gd:feedLink href=\"http://example.com/restaurants/SanFrancisco/432432/reviews\" > "
      "</gd:feedLink> <unkElement foo=\"bar\" /> <unkElement2 /> </gd:comments>" },
    { @"rel", @"http://schemas.google.com/g/2005#reviews" },
    { @"feedLink.href", @"http://example.com/restaurants/SanFrancisco/432432/reviews" },
    { @"unknownChildren.0.XMLString", @"<unkElement foo=\"bar\"></unkElement>" },
    { @"unknownChildren.1.XMLString", @"<unkElement2></unkElement2>" },
    { @"unknownChildren.@count.stringValue", @"2" },
    { @"", @"" },
    
    { @"GDataDeleted", @"<gd:deleted/>" },
    { @"unknownAttributes.@count.stringValue", @"0" },
    { @"unknownChildren.@count.stringValue", @"0" },
    { @"", @"" },
    
    { @"GDataContactSection", @"<gd:contactSection label=\"Work\"> "
      "<gd:email address=\"jo@example.com\" />"
      "<gd:phoneNumber rel=\"http://schemas.google.com/g/2005#work\">(650) 555-1212</gd:phoneNumber> "
      "<gd:phoneNumber rel=\"http://schemas.google.com/g/2005#pager\">(650) 555-1214</gd:phoneNumber> "
      "<gd:postalAddress>1600 Amphitheatre Pkwy\nMountain View, CA 94043</gd:postalAddress>"
      "<gd:geoPt label=\"fuzz\" time=\"2006-11-28T8:00:00-08:00\" lat=\"37.42\" lon=\"-122.08\"/> "
      "<gd:im protocol=\"sip\" address=\"foo@bar.example.com\"/>"
      "<gd:im protocol=\"aim\" address=\"fred the monster\"/> </gd:contactSection>" },
    { @"emails.0.address", @"jo@example.com" },
    { @"phoneNumbers.0.phoneNumber", @"(650) 555-1212" },
    { @"phoneNumbers.1.phoneNumber", @"(650) 555-1214" },
    { @"geoPts.0.label", @"fuzz" },
    { @"geoPts.0.lat.stringValue", @"37.42" },
    { @"geoPts.0.time.RFC3339String", @"2006-11-28T08:00:00-08:00" },
    { @"IMs.0.address", @"foo@bar.example.com" },
    { @"IMs.1.protocol", @"aim" },
    { @"", @"" },
        
    { @"GDataEmail", @"<gd:email label=\"Personal\" address=\"fubar@gmail.com\" />" },
    { @"label", @"Personal" },
    { @"address", @"fubar@gmail.com" },
    { @"", @"" },
    
    { @"GDataExtendedProperty", @"<gd:extendedProperty name='X-MOZ-ALARM-LAST-ACK' value='2006-10-03T19:01:14Z'/>" },
    { @"name", @"X-MOZ-ALARM-LAST-ACK" },
    { @"value", @"2006-10-03T19:01:14Z" },
    { @"", @"" },

    { @"GDataFeedLink", @"<gd:feedLink href='http://example.com/Jo/posts/MyFirstPost/comments' "
      "countHint=\"10\" readOnly=\"true\" />" },
    { @"href", @"http://example.com/Jo/posts/MyFirstPost/comments" },
    { @"countHint.stringValue", @"10" },
    { @"isReadOnly.stringValue", @"1" },
    { @"", @"" },
      
    // testing an inline feedLink
    { @"GDataFeedLink", inlinedFeedLinkStr },
    { @"href", nil },
    { @"isReadOnly.stringValue", @"0" },
    { @"feed.categories.0.term", kGDataCategorySpreadsheetCell },
    { @"feed.columnCount.stringValue", @"20" },
    { @"feed.entries.0.cell.column.stringValue", @"1" },
    { @"", @"" },
    
    
    { @"GDataGenerator", @" <generator version='1.0' uri='http://www.google.com/calendar/'>CL2</generator>" },
    { @"name", @"CL2" },
    { @"version", @"1.0" },
    { @"URI", @"http://www.google.com/calendar/" },
    { @"", @"" },
    
    { @"GDataGeoPt", @"<gd:geoPt lat=\"27.98778\" lon=\"86.94444\" elev=\"8850.0\" label=\"My GeoPt\" time=\"1996-12-19T16:39:57-08:00\"/>" },
    { @"label", @"My GeoPt" },
    { @"lat.stringValue", @"27.98778" },
    { @"lon.stringValue", @"86.94444" },
    { @"elev.stringValue", @"8850" },
    { @"time.RFC3339String", @"1996-12-19T16:39:57-08:00" },
    { @"", @"" },
      
    { @"GDataIM", @"<gd:im protocol='sip' address='foo@bar.example.com' label='fred' />" },
    { @"protocol", @"sip" },
    { @"address", @"foo@bar.example.com" },
    { @"label", @"fred" },
    { @"", @"" },
    
    { @"GDataLink", @"<link rel='alternate' type='text/html' "
      "href='http://www.google.com/calendar/event?stff' title='alternate' />" },
    { @"rel", @"alternate" },
    { @"type", @"text/html" },
    { @"href", @"http://www.google.com/calendar/event?stff" },
    { @"title", @"alternate" },
    { @"", @"" },
      
    { @"GDataOriginalEvent", @"<gd:originalEvent id=\"i8fl1nrv2bl57c1qgr3f0onmgg\" "
      "href=\"http://www.google.com/calendar/feeds/userID/private-magicCookie/full/eventID\" >"
      "<gd:when startTime=\"2006-03-17T22:00:00.000Z\"/>  </gd:originalEvent>" },
    { @"href", @"http://www.google.com/calendar/feeds/userID/private-magicCookie/full/eventID" },
    { @"originalID", @"i8fl1nrv2bl57c1qgr3f0onmgg" },
    { @"originalStartTime.startTime.RFC3339String", @"2006-03-17T22:00:00Z" }, // we generate +00:00 instead of Z
    { @"originalStartTime.endTime", nil },
    { @"originalStartTime.value", nil },
    { @"", @"" },
    
    { @"GDataPerson", @"<GDataPerson xml:lang='en'> <name>Greg Robbins</name> <email>test@froo.net</email> "
      "<uri>http://foo.com/</uri></GDataPerson>" },
    { @"name", @"Greg Robbins" },
    { @"nameLang", @"en" },
    { @"URI", @"http://foo.com/" },
    { @"email", @"test@froo.net" },
    { @"", @"" },
    
    { @"GDataPhoneNumber", @"<gd:phoneNumber rel='http://schemas.google.com/g/2005#work' "
      "label='work' uri='tel:+1-425-555-8080;ext=52585'>(425) 555-8080 ext. 52585</gd:phoneNumber>" },
    { @"rel", kGDataPhoneNumberWork },
    { @"URI", @"tel:+1-425-555-8080;ext=52585" },
    { @"label", @"work" },
    { @"phoneNumber", @"(425) 555-8080 ext. 52585" },
    { @"", @"" },
    
    { @"GDataPostalAddress", @"<gd:postalAddress label='work'>500 West 45th Street\nNew York, NY 10036</gd:postalAddress>" },
    { @"label", @"work" },
    { @"stringValue", @"500 West 45th Street\nNew York, NY 10036" },
    { @"", @"" },
    
    { @"GDataRating", @"<gd:rating rel='http://schemas.google.com/g/2005#price' value='5' min='1' max='5' />" },
    { @"rel", kGDataRatingPrice },
    { @"value.stringValue", @"5" },
    { @"min.stringValue", @"1" }, 
    { @"max.stringValue", @"5" },
    { @"", @"" },

    { @"GDataRecurrence", @"<gd:recurrence>DTSTART;TZID=America/Los_Angeles:200"
      "60314T060000\nDURATION:PT3600S</gd:recurrence>" },
    { @"stringValue", @"DTSTART;TZID=America/Los_Angeles:20060314T060000\nDURATION:PT3600S" },
    { @"", @"" },
    
    { @"GDataRecurrenceException", @"<gd:recurrenceException specialized='true'> <gd:entryLink "
      "href='http://gmail.com/jo/contacts/Jo' readOnly='true' /> "
      "<gd:originalEvent id='i8fl1nrv2bl57c1qgr3f0onmgg' href='http://www.google.com/href' >"
      "<gd:when startTime=\"2007-05-01T00:00:00.000Z\"/>  </gd:originalEvent></gd:recurrenceException>" },
    { @"isSpecialized.stringValue", @"1" },
    { @"entryLink.href", @"http://gmail.com/jo/contacts/Jo" },
    { @"entryLink.isReadOnly.stringValue", @"1" },
    { @"originalEvent.originalID", @"i8fl1nrv2bl57c1qgr3f0onmgg" },
    { @"originalEvent.originalStartTime.startTime.RFC3339String", @"2007-05-01T00:00:00Z" },
    { @"", @"" },
    
    { @"GDataReminder", @"<gd:reminder minutes='15' method='email' />" },
    { @"minutes", @"15" },
    { @"method", @"email" },
    { @"", @"" },

    { @"GDataTextConstruct", @"<title type='text' xml:lang='en'>Event title</title>" },
    { @"stringValue", @"Event title" },
    { @"lang", @"en" },
    { @"type", @"text" },
    { @"", @"" },
    
    { @"GDataTextConstruct", @"<title type='text'>Test ellipse (&#8230;) and others &quot;&lt;&amp;&gt;</title>" },
    { @"stringValue", textConstructTestResult }, // defined above
    { @"", @"" },    
    
    { @"GDataValueConstruct", @"<gCal:timezone value='America/Los_Angeles'/>" },
    { @"stringValue", @"America/Los_Angeles" },
    { @"", @"" },

    { @"GDataValueConstruct", @"<myValue value='1.51'/>" },
    { @"doubleValue.stringValue", @"1.51" },
    { @"", @"" },
      
    { @"GDataValueConstruct", @"<myValue value='987654321987'/>" },
    { @"longLongValue.stringValue", @"987654321987" },
    { @"", @"" },
    
    { @"GDataValueElementConstruct", @"<gCal:timezone>America/Los_Angeles</gCal:timezone>" },
    { @"stringValue", @"America/Los_Angeles" },
    { @"", @"" },
          
    { @"GDataBoolValueConstruct", @"<construct value='true'/>" },
    { @"boolValue.stringValue", @"1" },
    { @"", @"" },
    
    { @"GDataEntryContent", @"<content src='http://lh.google.com/image/Car.jpg' type='image/jpeg'/>" },
    { @"sourceURI", @"http://lh.google.com/image/Car.jpg" },
    { @"type", @"image/jpeg" },
    { @"", @"" },
      
    { @"GDataEntryContent", @"<title type='text' xml:lang='en'>Event title</title>" },
    { @"stringValue", @"Event title" },
    { @"lang", @"en" },
    { @"type", @"text" },
    { @"", @"" },
      
    { @"GDataWhen", @"<gd:when startTime='2005-06-06' endTime='2005-06-07' "
          "valueString='This weekend'/>" },
    { @"startTime.RFC3339String", @"2005-06-06" },
    { @"endTime.RFC3339String", @"2005-06-07" },
    { @"value", @"This weekend" },
    { @"", @"" },
    
    { @"GDataWhere", @"<gd:where rel='http://schemas.google.com/g/2005#event' "
      "label='main' valueString='The Pub'> "
      "<gd:entryLink href='http://local.example.com/10018/JoesPub' /></gd:where>" },
    { @"rel", kGDataCategoryEvent },
    { @"label", @"main" },
    { @"stringValue", @"The Pub" },
    { @"entryLink.href", @"http://local.example.com/10018/JoesPub" },
    { @"", @"" },
    
      
    // TODO(grobbins): test embedded entries
     { @"GDataWho", @"<gd:who rel=\"http://schemas.google.com/g/2005#event.attendee\" "
          "valueString=\"Jo\" email=\"jo@gmail.com\" >  "
          "<gd:attendeeType value=\"http://schemas.google.com/g/2005#event.required\"/> "
          "<gd:attendeeStatus value=\"http://schemas.google.com/g/2005#event.tentative\" /> "
          "<gd:entryLink href=\"http://gmail.com/jo/contacts/Jo\" readOnly=\"true\" />  </gd:who>" },
    { @"rel", kGDataWhoEventAttendee },
    { @"stringValue", @"Jo" },
    { @"email", @"jo@gmail.com" },
    { @"attendeeType.stringValue", kGDataWhoAttendeeTypeRequired },
    { @"attendeeStatus.stringValue", kGDataEventStatusTentative },
    { @"entryLink.href", @"http://gmail.com/jo/contacts/Jo" },
    { @"entryLink.isReadOnly.stringValue", @"1" },
    { @"", @"" },
    
    // Atom publishing control
    { @"GDataAtomPubControl", @"<app:control><app:draft>Yes</app:draft></app:control>" },
    { @"isDraft.stringValue", @"1" },
    { @"", @"" },
    
    // Batch elements
    { @"GDataBatchOperation", @"<batch:operation type='insert'/>" },
    { @"type", @"insert" },
    { @"", @"" },
    
    { @"GDataBatchID", @"<batch:id>item2</batch:id>" },
    { @"stringValue", @"item2" },
    { @"", @"" },
    
    { @"GDataBatchStatus", @"<batch:status  code='404' reason='Bad request' "
                          "content-type='application-text'>error</batch:status>" },
    { @"code.stringValue", @"404" },
    { @"reason", @"Bad request" },
    { @"contentType", @"application-text" },
    { @"stringValue", @"error" },
    { @"", @"" },
    
    { @"GDataBatchStatus", @"<batch:status  code='200' />" },
    { @"code.stringValue", @"200" },
    { @"reason", nil },
    { @"contentType", nil },
    { @"stringValue", @"" },
    { @"", @"" },

    { @"GDataBatchInterrupted", @"<batch:interrupted reason='no good reason' success='3' failures='4' parsed='7' />" },
    { @"reason", @"no good reason" },
    { @"successCount.stringValue", @"3" },
    { @"errorCount.stringValue", @"4" },
    { @"totalCount.stringValue", @"7" },
    { @"contentType", nil },
    { @"stringValue", @"" },
    { @"", @"" },
    
    { nil, nil }
  };
  
  [self runElementTests:tests];
}

- (void)testGoogleBaseElements {
  
  ElementTestKeyPathValues tests[] =
  {     
    { @"GDataGoogleBaseMetadataValue", @"<gm:value count='87269'>product fluggy</gm:value>>" },
    { @"count.stringValue", @"87269" },
    { @"contents", @"product fluggy" },
    { @"", @"" },
      
    { @"GDataGoogleBaseMetadataAttribute", @"<gm:attribute name='item type' type='text' count='116353'>"
      "<gm:value count='87269'>products</gm:value> <gm:value count='2401'>produkte</gm:value> "
      " </gm:attribute>" },
    { @"type", @"text" },
    { @"name", @"item type" },
    { @"count.stringValue", @"116353" },
    { @"values.@count.stringValue", @"2" },
    { @"values.1.count.stringValue", @"2401" },
    { @"values.1.contents", @"produkte" },
    { @"", @"" },
      
    { @"GDataGoogleBaseMetadataAttributeList", @"<gm:attributes>"
      "<gm:attribute name='location' type='location' />"
      "<gm:attribute name='delivery radius' type='floatUnit' />"
      "<gm:attribute name='payment' type='text' />       </gm:attributes>" },
    { @"attributes.@count.stringValue", @"3" },
    { @"attributes.0.name", @"location" },
    { @"attributes.2.type", @"text" },
    { @"", @"" },
      
    { @"GDataGoogleBaseMetadataItemType", @"<gm:item_type>business locations</gm:item_type>" },
    { @"value", @"business locations" },
    { @"", @"" },
      
    { @"GDataGoogleBaseAttribute", @"<g:product_type type='text'>Camera "
      "Connecting Cable<g:product_model> 65-798M </g:product_model>"
      "<g:product_revision> July06 </g:product_revision> </g:product_type>" },
    { @"name", @"product type" },
    { @"textValue", @"Camera Connecting Cable" },
    { @"", @"" },
    
    { nil, nil }
  };
  
  [self runElementTests:tests];
  
}

- (void)testSpreadsheetElements {
  
  ElementTestKeyPathValues tests[] =
  {     
    { @"GDataSpreadsheetCell", @"<gs:cell row='2' col='4' "
      " inputValue='=FLOOR(R[0]C[-1]/(R[0]C[-2]*60),.0001)'"
      " numericValue='0.0066'>0.0033</gs:cell>" },
    { @"row.stringValue", @"2" },
    { @"column.stringValue", @"4" },
    { @"inputString", @"=FLOOR(R[0]C[-1]/(R[0]C[-2]*60),.0001)" },
    { @"numericValue.stringValue", @"0.0066" },
    { @"resultString", @"0.0033" },
    { @"", @"" },
      
    { @"GDataRowCount", @"<gs:rowCount>100</gs:rowCount>" },
    { @"count.stringValue", @"100" },
    { @"", @"" },
      
    { @"GDataColumnCount", @"<gs:colCount>99</gs:colCount>" },
    { @"count.stringValue", @"99" },
    { @"", @"" },
      
    { @"GDataSpreadsheetCustomElement", @"<gsx:e-mail>fitzy@gmail.com</gsx:e-mail>" }, 
    { @"name", @"e-mail" },
    { @"stringValue", @"fitzy@gmail.com" },
    { @"", @"" },
      
    { nil, nil }
  };
  
  [self runElementTests:tests];
  
}

- (void)testMediaElements {
  
  ElementTestKeyPathValues tests[] =
  {     
    { @"GDataMediaContent", @"<media:content url='http://www.foo.com/movie.mov' "
        " fileSize='12216320' type='video/quicktime' medium='video' isDefault='true' "
        " expression='full' bitrate='128' framerate='25.1' samplingrate='44.1'"
        " channels='2' duration='185' height='200' width='300' "
        " lang='en' />" },
    { @"URLString", @"http://www.foo.com/movie.mov" },
    { @"fileSize.stringValue", @"12216320" },
    { @"type", @"video/quicktime" },
    { @"medium", @"video" },
    { @"isDefault.stringValue", @"1" },
    { @"expression", @"full" },
    { @"bitrate.stringValue", @"128" },
    { @"framerate.stringValue", @"25.1" },
    { @"samplingrate.stringValue", @"44.1" },
    { @"channels.stringValue", @"2" },
    { @"duration.stringValue", @"185" },
    { @"height.stringValue", @"200" },
    { @"width.stringValue", @"300" },
    { @"lang", @"en" },
    { @"", @"" },
    
    { @"GDataMediaThumbnail", @"<media:thumbnail url='http://www.foo.com/keyframe.jpg' "
          " width='75' height='50' time='12:05:01.123' />" },
    { @"URLString", @"http://www.foo.com/keyframe.jpg" },
    { @"width.stringValue", @"75" },
    { @"height.stringValue", @"50" },
    { @"time.timeOffsetInMilliseconds.stringValue", @"43501123" },
    { @"", @"" },
    
    { @"GDataMediaKeywords", @"<media:keywords>kitty, cat, big dog, yarn, fluffy</media:keywords>" },
    { @"keywords.0", @"kitty" },
    { @"keywords.2", @"big dog" },
    { @"keywords.@count.stringValue", @"5" },
    { @"", @"" },
    
    { @"GDataMediaCredit", @"<media:credit role='producer' scheme='urn:ebu'>entity name</media:credit>" },
    { @"role", @"producer" },
    { @"scheme", @"urn:ebu" },
    { @"stringValue", @"entity name" },
    { @"", @"" },
    
    { nil, nil }
  };
  
  [self runElementTests:tests];

}

- (void)testPhotoElements {
  
  ElementTestKeyPathValues tests[] =
  {     
    { @"GDataPhotoAlbumID", @"<gphoto:albumid>5024425138</gphoto:albumid>" },
    { @"stringValue", @"5024425138" },
    { @"", @"" },
      
    { @"GDataPhotoCommentCount", @"<gphoto:commentCount>11</gphoto:commentCount>" },
    { @"intValue.stringValue", @"11" }, // test the int accessor
    { @"", @"" },
      
    { @"GDataPhotoCommentingEnabled", @"<gphoto:commentingEnabled>true</gphoto:commentingEnabled>" },
    { @"stringValue", @"true" },
    { @"boolValue.stringValue", @"1" }, // test the bool accessor, too
    { @"", @"" },
      
    { @"GDataPhotoGPhotoID", @"<gphoto:id>512131187</gphoto:id>" },
    { @"stringValue", @"512131187" },
    { @"", @"" },
      
    { @"GDataPhotoMaxPhotosPerAlbum", @"<gphoto:maxPhotosPerAlbum>1000</gphoto:maxPhotosPerAlbum>" },
    { @"intValue.stringValue", @"1000" },
    { @"", @"" },
      
    { @"GDataPhotoNickname", @"<gphoto:nickname>Jane Smith</gphoto:nickname>" },
    { @"stringValue", @"Jane Smith" },
    { @"", @"" },
      
    { @"GDataPhotoQuotaUsed", @"<gphoto:quotacurrent>312459331</gphoto:quotacurrent>" },
    { @"longLongValue.stringValue", @"312459331" },
    { @"", @"" },
      
    { @"GDataPhotoQuotaLimit", @"<gphoto:quotalimit>1385222385</gphoto:quotalimit>" },
    { @"longLongValue.stringValue", @"1385222385" },
    { @"", @"" },
      
    { @"GDataPhotoThumbnail", @"<gphoto:thumbnail>http://picasaweb.google.com/image/.../Hello.jpg</gphoto:thumbnail>" },
    { @"stringValue", @"http://picasaweb.google.com/image/.../Hello.jpg" },
    { @"", @"" },
      
    { @"GDataPhotoUser", @"<gphoto:user>Jane</gphoto:user>" },
    { @"stringValue", @"Jane" },
    { @"", @"" },
      
    { @"GDataPhotoAccess", @"<gphoto:access>private</gphoto:access>" },
    { @"stringValue", @"private" },
    { @"", @"" },

    { @"GDataPhotoBytesUsed", @"<gphoto:bytesUsed>11876307</gphoto:bytesUsed>" },
    { @"longLongValue.stringValue", @"11876307" },
    { @"", @"" },
      
    { @"GDataPhotoLocation", @"<gphoto:location>Tokyo, Japan</gphoto:location>" },
    { @"stringValue", @"Tokyo, Japan" },
    { @"", @"" },
      
    { @"GDataPhotoName", @"<gphoto:name>mytrip</gphoto:name> " },
    { @"stringValue", @"mytrip" },
    { @"", @"" },
      
    { @"GDataPhotoNumberUsed", @"<gphoto:numphotos>237</gphoto:numphotos>" },
    { @"intValue.stringValue", @"237" },
    { @"", @"" },
      
    { @"GDataPhotoNumberLeft", @"<gphoto:numphotosremaining>763</gphoto:numphotosremaining>" },
    { @"intValue.stringValue", @"763" },
    { @"", @"" },
      
    { @"GDataPhotoChecksum", @"<gphoto:checksum>987123</gphoto:checksum>" },
    { @"stringValue", @"987123" },
    { @"", @"" },
      
    { @"GDataPhotoClient", @"<gphoto:client>Picasa1.2</gphoto:client>" },
    { @"stringValue", @"Picasa1.2" },
    { @"", @"" },
      
    { @"GDataPhotoHeight", @"<gphoto:height>1200</gphoto:height>" },
    { @"longLongValue.stringValue", @"1200" },
    { @"", @"" },
      
    { @"GDataPhotoPosition", @"<gphoto:position>10</gphoto:position>" },
    { @"intValue.stringValue", @"10" },
    { @"", @"" },
      
    { @"GDataPhotoRotation", @"<gphoto:rotation>90</gphoto:rotation>" },
    { @"intValue.stringValue", @"90" },
    { @"", @"" },
      
    { @"GDataPhotoSize", @"<gphoto:size>149351</gphoto:size>" },
    { @"longLongValue.stringValue", @"149351" },
    { @"", @"" },
      
    { @"GDataPhotoTimestamp", @"<gphoto:timestamp>1168640584000</gphoto:timestamp>" },
    { @"longLongValue.stringValue", @"1168640584000" },
    { @"", @"" },
      
    { @"GDataPhotoVersion", @"<gphoto:version>v22838</gphoto:version>" },
    { @"stringValue", @"v22838" },
    { @"", @"" },
      
    { @"GDataPhotoWidth", @"<gphoto:width>1600</gphoto:width>" },
    { @"longLongValue.stringValue", @"1600" },
    { @"", @"" },
      
    { @"GDataPhotoPhotoID", @"<gphoto:photoid>301521187</gphoto:photoid>" },
    { @"stringValue", @"301521187" },
    { @"", @"" },
      
    { @"GDataPhotoWeight", @"<gphoto:weight>3</gphoto:weight>" },
    { @"intValue.stringValue", @"3" },
    { @"", @"" },
    
    { @"GDataEXIFTags", @"<exif:tags><exif:fstop>0.0</exif:fstop>"
      "<exif:make>Nokia</exif:make><exif:model>6133</exif:model>"
      "<exif:distance>0.0</exif:distance><exif:exposure>0.0</exif:exposure>"
      "<exif:model>Second Model</exif:model><exif:flash>true</exif:flash>"
      "</exif:tags>" }, // intentional second copy of "model" tag
    { @"tags.@count.stringValue", @"7" },
    { @"tagDictionary.make", @"Nokia" },
    { @"tagDictionary.model", @"6133" }, // first instance of "model" tag
    { @"", @"" },
      
    { nil, nil }
  };
  
  [self runElementTests:tests];
  
}

- (void)testGeo {
  ElementTestKeyPathValues tests[] =
  {     
    // test explicit types - here we specify which subclass of GDataGeo
    // to instantiate
    { @"GDataGeoW3CPoint", @"<geo:Point><geo:lat>55.701</geo:lat>"
        "<geo:long>12.552</geo:long></geo:Point>" },
    { @"latitude.stringValue", @"55.701" },
    { @"longitude.stringValue", @"12.552" },
    { @"isPoint.stringValue", @"1" },
    { @"", @"" },
      
    { @"GDataGeoRSSPoint", @"<georss:point>45.256 -71.92</georss:point>" },
    { @"latitude.stringValue", @"45.256" },
    { @"longitude.stringValue", @"-71.92" },
    { @"", @"" },
      
    { @"GDataGeoRSSWhere", @"<georss:where><gml:Point><gml:pos>45.256 -71.92"
        "</gml:pos></gml:Point></georss:where>" },
    { @"latitude.stringValue", @"45.256" },
    { @"longitude.stringValue", @"-71.92" },
    { @"", @"" },
    
    // test GDataGeo for implicit types - here we use
    // a test class which incorporates uses GDataGeo's utilities for 
    // determining the subclass of GDataGeo to instantiate
    //
    // GDataGeoTestClass is defined below in this file
    { @"GDataGeoTestClass", @"<GDataGeoTestClass><geo:Point><geo:lat>55.701</geo:lat>" // W3CPoint
        "<geo:long>12.552</geo:long></geo:Point></GDataGeoTestClass>" },
    { @"geoLocation.latitude.stringValue", @"55.701" },
    { @"geoLocation.longitude.stringValue", @"12.552" },
    { @"", @"" },
      
    { @"GDataGeoTestClass", @"<GDataGeoTestClass><georss:point>0.256 -71.92"
        "</georss:point></GDataGeoTestClass>" }, // RSSPoint
    { @"geoLocation.latitude.stringValue", @"0.256" },
    { @"geoLocation.longitude.stringValue", @"-71.92" },
    { @"", @"" },
      
    { @"GDataGeoTestClass", @"<GDataGeoTestClass><georss:where><gml:Point><gml:pos>-1.256 -71.92" // RSSWhere
      "</gml:pos></gml:Point></georss:where></GDataGeoTestClass>" },
    { @"geoLocation.latitude.stringValue", @"-1.256" },
    { @"geoLocation.longitude.stringValue", @"-71.92" },
    { @"", @"" },
    
    { nil, nil }
  };
  
  [self runElementTests:tests];
  
}


- (void)testPicasaWebQuery {
  
  GDataQueryPicasaWeb *pwaQuery1;
  pwaQuery1 = [GDataQueryPicasaWeb picasaWebQueryForUserID:@"fredflintstone"
                                                   albumID:@"12345"
                                                 albumName:nil
                                                   photoID:@"987654321"];
  [pwaQuery1 setKind:kGDataPicasaWebKindPhoto];
  [pwaQuery1 setAccess:kGDataPicasaWebAccessPrivate];
  [pwaQuery1 setThumbsize:80];
    
  NSURL* resultURL1 = [pwaQuery1 URL];
  NSString *expected1 = @"http://picasaweb.google.com/data/feed/api/"
    "user/fredflintstone/albumid/12345/photoid/987654321?"
    "thumbsize=80&access=private&kind=photo";
  STAssertEqualObjects([resultURL1 absoluteString], expected1, 
                       @"PWA query 1 generation error");
  

  GDataQueryPicasaWeb *pwaQuery2; 
  pwaQuery2 = [GDataQueryPicasaWeb picasaWebQueryForUserID:@"fredflintstone"
                                                   albumID:nil
                                                 albumName:@"froggy photos"
                                                   photoID:nil];  
  NSURL* resultURL2 = [pwaQuery2 URL];
  NSString *expected2 = @"http://picasaweb.google.com/data/feed/api/user/fredflintstone/album/froggy%20photos";
  STAssertEqualObjects([resultURL2 absoluteString], expected2, 
                       @"PWA query 2 generation error");
}



- (void)testChangedNamespace {
  
  // We'll allocate three objects which are equivalent except for 
  // differing namespace prefix declarations.
  
  // create with normal namespaces, including default of atom
  NSString * const xml0 = @"<entry xmlns=\"http://www.w3.org/2005/Atom\""
  " xmlns:gd=\"http://schemas.google.com/g/2005\"  >"
  " <gd:comments rel=\"http://schemas.google.com/g/2005#reviews\"> "
  "<gd:feedLink href=\"http://example.com/restaurants/SanFrancisco/432432/reviews\" > "
  "</gd:feedLink> <unkElement foo=\"bar\" /> <unkElement2 /> </gd:comments> </entry>";
  
  // use gx instead of gd for namespace prefix
  NSString * const xml1 = @"<entry xmlns=\"http://www.w3.org/2005/Atom\""
    " xmlns:gx=\"http://schemas.google.com/g/2005\"  >"
    " <gx:comments rel=\"http://schemas.google.com/g/2005#reviews\"> "
    "<gx:feedLink href=\"http://example.com/restaurants/SanFrancisco/432432/reviews\" > "
    "</gx:feedLink> <unkElement foo=\"bar\" /> <unkElement2 /> </gx:comments> </entry>";
  
  // make gd the default prefix, declare atom explicitly
  NSString * const xml2 = @"<entry xmlns:atom=\"http://www.w3.org/2005/Atom\""
  " xmlns=\"http://schemas.google.com/g/2005\"  >"
  " <comments rel=\"http://schemas.google.com/g/2005#reviews\"> "
  "<feedLink href=\"http://example.com/restaurants/SanFrancisco/432432/reviews\" > "
  "</feedLink> <unkElement foo=\"bar\" /> <unkElement2 /> </comments> </entry>";
  
  GDataObject *obj0 = [self GDataObjectForClassName:[GDataComment class]
                                          XMLString:xml0
                    shouldWrapWithNamespaceAndEntry:NO];
  STAssertNotNil(obj0, @"%@", obj0);

  GDataObject *obj1 = [self GDataObjectForClassName:[GDataComment class]
                                          XMLString:xml1
                    shouldWrapWithNamespaceAndEntry:NO];
  STAssertNotNil(obj1, @"%@", obj1);
  
  GDataObject *obj2 = [self GDataObjectForClassName:[GDataComment class]
                                          XMLString:xml2
                    shouldWrapWithNamespaceAndEntry:NO];
  STAssertNotNil(obj2, @"%@", obj2);
  
  STAssertEqualObjects(obj0, obj1, @"namespace interpretations should have made matching objects\n  %@\n!=\n  %@",
                       [obj0 XMLElement], [obj1 XMLElement]);
  STAssertEqualObjects(obj1, obj2, @"namespace interpretations should have made matching objects\n  %@\n!=\n  %@",
                       [obj1 XMLElement], [obj2 XMLElement]);
}

@end

// class for testing GDataGeo (used above)
@interface GDataGeoTestClass : GDataObject
@end

@implementation GDataGeoTestClass

- (void)initExtensionDeclarations {
  [super initExtensionDeclarations];
  
  [GDataGeo addGeoExtensionDeclarationsToObject:self
                                 forParentClass:[self class]];
}

- (NSXMLElement *)XMLElement {
  
  NSXMLElement *element = [self XMLElementWithExtensionsAndDefaultName:@"GDataGeoTestClass"];
  return element;
}

#pragma mark -

- (GDataGeo *)geoLocation {
  return [GDataGeo geoLocationForObject:self];
}

- (void)setGeoLocation:(GDataGeo *)geo {
  [GDataGeo setGeoLocation:geo forObject:self];
}

@end
