// Fixture: tautological and decorative tests.

describe("user service", () => {
  test("creates a user", () => {
    const user = createUser("alice");
    expect(user).toBeDefined();
  });

  test("does not return null", () => {
    const result = fetchUser(1);
    expect(result).not.toBeNull();
  });

  test("equals itself", () => {
    const x = compute(2);
    expect(x).toEqual(x);
  });

  test.skip("login flow", () => {
    // FIXME: implement
  });

  it("real test", () => {
    expect(compute(2)).toEqual(4);
  });
});
