import XCTest
@testable import BlocksCodegen

final class CodegenModelBuilderTests: XCTestCase {
    let parser = OpenRPCParser()
    let builder = CodegenModelBuilder()

    private func buildModel(from json: String) throws -> CodegenModel {
        let rpcModel = try parser.parse(data: json.data(using: .utf8)!)
        return builder.build(from: rpcModel)
    }

    // MARK: - Namespace Grouping

    func testGroupsMethodsByNamespace() throws {
        let model = try buildModel(from: """
        {
            "openrpc": "1.3.2",
            "info": { "title": "test", "version": "1.0.0" },
            "methods": [
                { "name": "api.create", "params": [], "result": { "name": "R", "schema": { "type": "boolean" } } },
                { "name": "api.delete", "params": [], "result": { "name": "R", "schema": { "type": "boolean" } } },
                { "name": "auth.login", "params": [], "result": { "name": "R", "schema": { "type": "boolean" } } }
            ]
        }
        """)

        XCTAssertEqual(model.apiNamespaces.count, 2)
        let apiNs = model.apiNamespaces.first { $0.name == "api" }
        let authNs = model.apiNamespaces.first { $0.name == "auth" }
        XCTAssertEqual(apiNs?.operations.count, 2)
        XCTAssertEqual(authNs?.operations.count, 1)
    }

    // MARK: - Type Resolution

    func testResolvesInlineObject() throws {
        let model = try buildModel(from: """
        {
            "openrpc": "1.3.2",
            "info": { "title": "test", "version": "1.0.0" },
            "methods": [{
                "name": "api.get",
                "params": [],
                "result": { "name": "Todo", "schema": { "type": "object", "properties": { "title": { "type": "string" }, "done": { "type": "boolean" } }, "required": ["title", "done"] } }
            }]
        }
        """)

        let op = model.apiNamespaces[0].operations[0]
        if case .record(let name, let fields, _, _) = op.result.type {
            XCTAssertEqual(name, "Result")
            XCTAssertEqual(fields.count, 2)
            XCTAssertTrue(fields.allSatisfy { $0.required })
        } else {
            XCTFail("Expected record type")
        }
    }

    func testResolvesNullableType() throws {
        let model = try buildModel(from: """
        {
            "openrpc": "1.3.2",
            "info": { "title": "test", "version": "1.0.0" },
            "methods": [{
                "name": "api.get",
                "params": [{ "name": "val", "required": true, "schema": { "oneOf": [{ "type": "string" }, { "type": "null" }] } }],
                "result": { "name": "R", "schema": { "type": "string" } }
            }]
        }
        """)

        let param = model.apiNamespaces[0].operations[0].parameters[0]
        if case .nullable(let inner) = param.type {
            if case .primitive(.string, _) = inner {
                // correct
            } else {
                XCTFail("Expected nullable(string)")
            }
        } else {
            XCTFail("Expected nullable type")
        }
    }

    func testResolvesEnumType() throws {
        let model = try buildModel(from: """
        {
            "openrpc": "1.3.2",
            "info": { "title": "test", "version": "1.0.0" },
            "methods": [{
                "name": "api.get",
                "params": [{ "name": "status", "required": true, "schema": { "type": "string", "enum": ["active", "inactive"] } }],
                "result": { "name": "R", "schema": { "type": "string" } }
            }]
        }
        """)

        let param = model.apiNamespaces[0].operations[0].parameters[0]
        if case .enum(let name, let values) = param.type {
            XCTAssertEqual(values, ["active", "inactive"])
            XCTAssertFalse(name.isEmpty)
        } else {
            XCTFail("Expected enum type")
        }
    }

    func testResolvesMapType() throws {
        let model = try buildModel(from: """
        {
            "openrpc": "1.3.2",
            "info": { "title": "test", "version": "1.0.0" },
            "methods": [{
                "name": "api.get",
                "params": [],
                "result": { "name": "Scores", "schema": { "type": "object", "additionalProperties": { "type": "number" } } }
            }]
        }
        """)

        let op = model.apiNamespaces[0].operations[0]
        if case .map(let valueType) = op.result.type {
            if case .primitive(.number, _) = valueType {
                // correct
            } else {
                XCTFail("Expected map with number value")
            }
        } else {
            XCTFail("Expected map type")
        }
    }

    func testResolvesSchemaRef() throws {
        let model = try buildModel(from: """
        {
            "openrpc": "1.3.2",
            "info": { "title": "test", "version": "1.0.0" },
            "methods": [{
                "name": "api.get",
                "params": [],
                "result": { "name": "R", "schema": { "$ref": "#/components/schemas/Todo" } }
            }],
            "components": {
                "schemas": {
                    "Todo": { "type": "object", "properties": { "title": { "type": "string" } }, "required": ["title"] }
                }
            }
        }
        """)

        let op = model.apiNamespaces[0].operations[0]
        // After dropping structural deduplication,
        // a $ref resolves to a typeReference pointing at the component
        // schema's declared name. The component itself is registered as a
        // top-level TypeDefinition under that name.
        if case .typeReference(let name) = op.result.type {
            XCTAssertEqual(name, "Todo")
        } else {
            XCTFail("Expected typeReference from schema ref")
        }
        XCTAssertTrue(
            model.typeDefinitions.contains { $0.name == "Todo" },
            "Component schema Todo must be registered as a top-level type"
        )
    }

    // MARK: - Discriminator Detection

    func testDetectsDiscriminatedUnion() throws {
        let model = try buildModel(from: """
        {
            "openrpc": "1.3.2",
            "info": { "title": "test", "version": "1.0.0" },
            "methods": [{
                "name": "api.act",
                "params": [{ "name": "input", "required": true, "schema": {
                    "oneOf": [
                        { "type": "object", "properties": { "action": { "type": "string", "enum": ["create"] }, "title": { "type": "string" } }, "required": ["action", "title"] },
                        { "type": "object", "properties": { "action": { "type": "string", "enum": ["delete"] }, "id": { "type": "string" } }, "required": ["action", "id"] }
                    ]
                }}],
                "result": { "name": "R", "schema": { "type": "boolean" } }
            }]
        }
        """)

        let param = model.apiNamespaces[0].operations[0].parameters[0]
        if case .union(_, let variants, let discriminator) = param.type {
            XCTAssertNotNil(discriminator)
            XCTAssertEqual(discriminator?.fieldName, "action")
            XCTAssertEqual(variants.count, 2)
        } else {
            XCTFail("Expected union type")
        }
    }
}
