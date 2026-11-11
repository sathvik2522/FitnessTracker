import XCTest
#if SWIFT_PACKAGE
@testable import PersonalFitnessCore
#else
@testable import PersonalFitness
#endif

final class OfflineCatalogTests: XCTestCase {
    func catalog(_ name: String) throws -> OfflineCatalog {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("PersonalFitness/Resources/Catalogs/\(name)-v1.json"))
        return try JSONDecoder().decode(OfflineCatalog.self, from: data).validated()
    }
    func testShippedCatalogsValidateSourceLicenseAndEveryDeterministicIdentity() throws {
        let foods = try catalog("foods"), exercises = try catalog("exercises")
        XCTAssertGreaterThan(foods.foods.count, 700); XCTAssertEqual(exercises.exercises.count, 876)
        XCTAssertEqual(foods.source.license, "CC0-1.0"); XCTAssertEqual(exercises.source.license, "Unlicense")
        XCTAssertTrue(foods.source.downloadURL.hasPrefix("https://fdc.nal.usda.gov/"))
        XCTAssertTrue(exercises.source.downloadURL.contains(exercises.release))
        XCTAssertEqual(CatalogIdentity.id(source: foods.source.id, record: foods.foods[0].recordID), foods.foods[0].id)
        var invalid = foods; invalid.schemaVersion = 99; XCTAssertThrowsError(try invalid.validated())
        invalid = foods; invalid.source.license = "Unknown"; XCTAssertThrowsError(try invalid.validated())
        invalid = foods; invalid.source.attribution = ""; XCTAssertThrowsError(try invalid.validated())
        invalid = foods; invalid.foods.append(invalid.foods[0]); XCTAssertThrowsError(try invalid.validated())
    }
    func testRequestedFoodAndGymFamiliesHaveSearchableSourceRecords() throws {
        let foods = try catalog("foods").foods.map(\.definition)
        for query in ["egg whole", "chicken breast", "rice", "mung beans", "yogurt plain", "greek yogurt", "cottage cheese", "sweet potato", "apple", "grapes", "watermelon", "whey protein", "jeera", "haldi", "rajma"] {
            XCTAssertTrue(foods.contains { CatalogSearch.matches(query, name: $0.name, aliases: $0.aliases ?? []) }, query)
        }
        let exercises = try catalog("exercises").exercises.map(\.exercise)
        for query in ["bench press", "chest fly", "row", "overhead press", "lateral raise", "assisted pull", "hack squat", "leg press", "leg curl", "Bulgarian split squat", "hip thrust"] {
            XCTAssertTrue(exercises.contains { CatalogSearch.matches(query, name: $0.name, aliases: $0.aliases ?? []) }, query)
        }
        XCTAssertTrue(exercises.contains { $0.category == "cardio" })
    }
    func testMissingMacrosNeverDecodeAsZeroAndOldUserDefinitionsRemainReadable() throws {
        let item = try catalog("foods").foods[0].definition
        let data = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
        var nutrients = try XCTUnwrap(object["nutrients"] as? [String:Any]); nutrients.removeValue(forKey: "fat"); object["nutrients"] = nutrients
        XCTAssertThrowsError(try JSONDecoder().decode(FoodDefinition.self, from: JSONSerialization.data(withJSONObject: object)))
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
        for key in ["catalog","aliases","sourceServings"] { object.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(FoodDefinition.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.catalog); XCTAssertNil(legacy.aliases); XCTAssertEqual(legacy.nutrients, item.nutrients)
    }
    func testMungRawCookedAliasesAndExplicitSourceServingScale() throws {
        let foods = try catalog("foods").foods.map(\.definition)
        let raw = try XCTUnwrap(foods.first { $0.name == "Mung beans, mature seeds, raw" })
        let cooked = try XCTUnwrap(foods.first { $0.name == "Mung beans, mature seeds, cooked, boiled, without salt" })
        XCTAssertEqual(raw.preparation, .raw); XCTAssertEqual(cooked.preparation, .cooked)
        XCTAssertNotEqual(raw.nutrients, cooked.nutrients)
        XCTAssertTrue(CatalogSearch.matches("moong raw", name: raw.name, aliases: raw.aliases ?? []))
        XCTAssertFalse(CatalogSearch.matches("urad", name: raw.name, aliases: raw.aliases ?? []))
        XCTAssertThrowsError(try raw.scaled(quantity: 100, unit: .milliliters))
        let portion = try XCTUnwrap(raw.sourceServings?.first)
        XCTAssertEqual(try raw.scaled(quantity: 1, unit: .servings).calories, raw.nutrients.calories * portion.gramWeight / 100, accuracy: 0.000001)
        let ingredient = RecipeIngredient(food: raw, quantity: 50, unit: .grams)
        XCTAssertEqual(try RecipeCalculation.perServing([ingredient,ingredient], servings: 2).protein, raw.nutrients.protein / 2, accuracy: 0.000001)
    }
    func testThreeWayMergeProtectsUserFieldsAndNutritionBasis() throws {
        let catalog = try self.catalog("foods"), record = catalog.foods[0]
        let baseline = record.definition
        var current = baseline
        current.catalog = catalog.origin(record: record.recordID, quality: record.quality, baseline: try JSONEncoder().encode(baseline))
        current.name = "My food name"; current.referenceQuantity = 1
        var incoming = baseline; incoming.name = "Source corrected name"; incoming.nutrients.calories += 10; incoming.aliases = ["new alias"]
        var origin = current.catalog!; origin.release = "next"; origin.baseline = try JSONEncoder().encode(incoming)
        let merged = try CatalogMerge.food(current: current, incoming: incoming, origin: origin)
        XCTAssertEqual(merged.name, "My food name"); XCTAssertEqual(merged.referenceQuantity, 1)
        XCTAssertEqual(merged.nutrients, baseline.nutrients, "Serving basis and macros must update atomically")
        XCTAssertEqual(merged.aliases, ["new alias"]); XCTAssertEqual(merged.catalog?.userModified, true)
        current = baseline; current.catalog = origin
        current.catalog?.baseline = try JSONEncoder().encode(baseline)
        let untouched = try CatalogMerge.food(current: current, incoming: incoming, origin: origin)
        XCTAssertEqual(untouched.nutrients, incoming.nutrients); XCTAssertEqual(untouched.name, incoming.name)
    }
    func testExerciseAliasesSourceInstructionsAndUserNoteMerge() throws {
        let catalog = try self.catalog("exercises")
        let item = try XCTUnwrap(catalog.exercises.first { $0.recordID == "Split_Squat_with_Dumbbells" })
        XCTAssertTrue(CatalogSearch.matches("Bulgarian split squat", name: item.exercise.name, aliases: item.exercise.aliases ?? []))
        XCTAssertFalse(item.exercise.instructions!.isEmpty)
        var current = item.exercise
        current.catalog = catalog.origin(record: item.recordID, quality: item.quality, baseline: try JSONEncoder().encode(item.exercise))
        current.notes = "My gym notes"
        var incoming = item.exercise; incoming.equipment = "Source equipment correction"
        var origin = current.catalog!; origin.baseline = try JSONEncoder().encode(incoming)
        let merged = try CatalogMerge.exercise(current: current, incoming: incoming, origin: origin)
        XCTAssertEqual(merged.notes, "My gym notes"); XCTAssertEqual(merged.equipment, incoming.equipment)
        XCTAssertTrue(merged.catalog!.userModified)
    }
}
