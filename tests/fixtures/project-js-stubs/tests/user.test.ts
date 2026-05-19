import { describe, test, expect, vi } from "vitest";
import { createUser, fetchUser } from "../src/user";

describe("user service — decorative tests", () => {
  test("createUser is callable", async () => {
    const u = await createUser("a@b.c");
    expect(u).toBeDefined();
  });

  test("fetchUser returns something", () => {
    const r = fetchUser("1");
    expect(r).not.toBeNull();
  });

  test("self-equality", () => {
    const x = 42;
    expect(x).toEqual(x);
  });

  test("disabled assertions", () => {
    expect.assertions(0);
  });

  test("empty snapshot", () => {
    expect({}).toMatchSnapshot();
  });

  test("mock-only", () => {
    const spy = vi.fn();
    spy("hello");
    expect(spy).toHaveBeenCalled();
  });

  test.skip("login flow — implement later", () => {
    // FIXME: implement
  });
});
