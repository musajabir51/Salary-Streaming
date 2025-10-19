import { describe, expect, it, beforeEach } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const employee1 = accounts.get("wallet_1")!;
const employee2 = accounts.get("wallet_2")!;
const employee3 = accounts.get("wallet_3")!;

describe("Salary Streaming with Employee Leave Management", () => {
  
  // ===========================
  // CORE FUNCTIONALITY TESTS
  // ===========================
  
  describe("Contract Initialization", () => {
    it("initializes contract correctly", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "initialize-contract",
        [],
        deployer
      );
      expect(result).toBeOk(true);
    });

    it("prevents non-owner from initializing", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "initialize-contract",
        [],
        employee1
      );
      expect(result).toBeErr("u100"); // ERR-NOT-AUTHORIZED
    });
  });

  describe("Employee Management", () => {
    it("adds employee successfully with leave balance initialization", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"], // $25/hour
        deployer
      );
      expect(result).toBeOk(true);

      // Check employee info
      const employeeInfo = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-employee-info",
        [`'${employee1}`],
        deployer
      );
      expect(employeeInfo.result).toBeOk(expect.objectContaining({
        "hourly-rate": "u2500",
        "active": true,
        "total-earned": "u0"
      }));

      // Check that leave balances were initialized
      const leaveBalance = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-employee-leave-summary",
        [`'${employee1}`],
        deployer
      );
      expect(leaveBalance.result).toBeOk(expect.objectContaining({
        vacation: expect.objectContaining({ "available-hours": "u0" }),
        sick: expect.objectContaining({ "available-hours": "u0" }),
        personal: expect.objectContaining({ "available-hours": "u0" })
      }));
    });

    it("prevents adding duplicate employee", () => {
      // Add employee first
      simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"],
        deployer
      );

      // Try to add same employee again
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u3000"],
        deployer
      );
      expect(result).toBeErr("u103"); // ERR-EMPLOYEE-EXISTS
    });

    it("prevents non-owner from adding employee", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"],
        employee2
      );
      expect(result).toBeErr("u100"); // ERR-NOT-AUTHORIZED
    });

    it("updates employee rate successfully", () => {
      // Add employee first
      simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"],
        deployer
      );

      // Update rate
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "update-employee-rate",
        [`'${employee1}`, "u3000"],
        deployer
      );
      expect(result).toBeOk(true);

      // Verify update
      const employeeInfo = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-employee-info",
        [`'${employee1}`],
        deployer
      );
      expect(employeeInfo.result).toBeOk(expect.objectContaining({
        "hourly-rate": "u3000"
      }));
    });
  });

  describe("Treasury Management", () => {
    it("deposits funds successfully", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "deposit-funds",
        ["u100000"],
        deployer
      );
      expect(result).toBeOk(true);

      const balance = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-treasury-balance",
        [],
        deployer
      );
      expect(balance.result).toBeOk("u100000");
    });

    it("rejects invalid deposit amounts", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "deposit-funds",
        ["u0"],
        deployer
      );
      expect(result).toBeErr("u101"); // ERR-INVALID-AMOUNT
    });
  });

  describe("Streaming Payments", () => {
    beforeEach(() => {
      // Set up employee and treasury
      simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"],
        deployer
      );
      simnet.callPublicFn(
        "Salary-Streaming",
        "deposit-funds",
        ["u100000"],
        deployer
      );
    });

    it("starts stream successfully", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "start-stream",
        [`'${employee1}`, "u50000", "u1000"], // $500, 1000 blocks
        deployer
      );
      expect(result).toBeOk(true);

      // Check stream info
      const streamInfo = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-stream-info",
        [`'${employee1}`],
        deployer
      );
      expect(streamInfo.result).toBeOk(expect.objectContaining({
        amount: "u50000",
        claimed: "u0",
        paused: false
      }));
    });

    it("calculates claimable amount correctly", () => {
      simnet.callPublicFn(
        "Salary-Streaming",
        "start-stream",
        [`'${employee1}`, "u50000", "u1000"],
        deployer
      );

      // Advance blocks
      simnet.mineEmptyBlocks(100);

      const claimable = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-claimable-amount",
        [`'${employee1}`],
        deployer
      );
      
      // Should be approximately 10% of total (100/1000 blocks)
      expect(claimable.result).toBeOk("u5000");
    });
  });

  // ===========================
  // LEAVE MANAGEMENT TESTS
  // ===========================

  describe("Leave Balance Management", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"],
        deployer
      );
    });

    it("initializes leave balances correctly for new employee", () => {
      const leaveSummary = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-employee-leave-summary",
        [`'${employee1}`],
        deployer
      );

      expect(leaveSummary.result).toBeOk({
        vacation: {
          "available-hours": "u0",
          "used-hours": "u0", 
          "accrued-hours": "u0",
          "last-updated": expect.any(String)
        },
        sick: {
          "available-hours": "u0",
          "used-hours": "u0",
          "accrued-hours": "u0", 
          "last-updated": expect.any(String)
        },
        personal: {
          "available-hours": "u0",
          "used-hours": "u0",
          "accrued-hours": "u0",
          "last-updated": expect.any(String)
        }
      });
    });

    it("accrues leave hours after sufficient time", () => {
      // Advance sufficient blocks for accrual (2160+ blocks)
      simnet.mineEmptyBlocks(2200);

      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "accrue-leave-hours",
        [`'${employee1}`],
        deployer
      );
      expect(result).toBeOk(true);

      // Check that vacation leave was accrued (120/12 = 10 hours monthly)
      const vacationBalance = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-balance",
        [`'${employee1}`, "u1"], // LEAVE-TYPE-VACATION
        deployer
      );
      expect(vacationBalance.result).toEqual({
        "available-hours": "u10",
        "used-hours": "u0",
        "accrued-hours": "u10",
        "last-updated": expect.any(String)
      });
    });

    it("prevents accrual too early", () => {
      // Only advance a few blocks (less than 2160)
      simnet.mineEmptyBlocks(100);

      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "accrue-leave-hours",
        [`'${employee1}`],
        deployer
      );
      expect(result).toBeOk(false); // Returns false when not time to accrue
    });
  });

  describe("Leave Requests", () => {
    beforeEach(() => {
      // Set up employee with some leave balance
      simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"],
        deployer
      );
      
      // Advance blocks and accrue leave
      simnet.mineEmptyBlocks(2200);
      simnet.callPublicFn(
        "Salary-Streaming",
        "accrue-leave-hours",
        [`'${employee1}`],
        deployer
      );
    });

    it("submits leave request successfully", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u1", "u1000", "u1008", "u8", "\"Vacation to Hawaii\""], // vacation, 1 day = 8 hours
        employee1
      );
      expect(result).toBeOk("u1"); // Returns request ID

      // Verify request was created
      const requestInfo = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-request",
        ["u1"],
        deployer
      );
      expect(requestInfo.result).toBeOk(expect.objectContaining({
        employee: employee1,
        "leave-type": "u1",
        "start-date": "u1000",
        "end-date": "u1008", 
        "hours-requested": "u8",
        status: "u0", // pending
        reason: "\"Vacation to Hawaii\""
      }));
    });

    it("rejects request with insufficient balance", () => {
      // Try to request more hours than available (10 hours available, requesting 16)
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u1", "u1000", "u1016", "u16", "\"Long vacation\""],
        employee1
      );
      expect(result).toBeErr("u111"); // ERR-INSUFFICIENT-LEAVE-BALANCE
    });

    it("rejects invalid leave type", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u4", "u1000", "u1008", "u8", "\"Invalid type\""], // Invalid leave type
        employee1
      );
      expect(result).toBeErr("u110"); // ERR-INVALID-LEAVE-TYPE
    });

    it("rejects invalid date range", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u1", "u1008", "u1000", "u8", "\"Invalid dates\""], // end < start
        employee1
      );
      expect(result).toBeErr("u116"); // ERR-INVALID-DATE-RANGE
    });

    it("prevents non-employee from submitting request", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u1", "u1000", "u1008", "u8", "\"Not an employee\""],
        employee2 // Not added as employee
      );
      expect(result).toBeErr("u104"); // ERR-NO-EMPLOYEE
    });
  });

  describe("Leave Request Processing", () => {
    beforeEach(() => {
      // Set up employee with leave balance and submit a request
      simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee", 
        [`'${employee1}`, "u2500"],
        deployer
      );
      simnet.mineEmptyBlocks(2200);
      simnet.callPublicFn(
        "Salary-Streaming",
        "accrue-leave-hours",
        [`'${employee1}`],
        deployer
      );
      simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u1", "u1000", "u1008", "u8", "\"Vacation request\""],
        employee1
      );
    });

    it("approves leave request successfully", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "process-leave-request",
        ["u1", "true"], // approve
        deployer
      );
      expect(result).toBeOk(true);

      // Check request status
      const requestInfo = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-request",
        ["u1"],
        deployer
      );
      expect(requestInfo.result).toBeOk(expect.objectContaining({
        status: "u1", // approved
        "processed-by": `(some ${deployer})`
      }));

      // Check leave balance was deducted
      const balance = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-balance",
        [`'${employee1}`, "u1"],
        deployer
      );
      expect(balance.result).toEqual({
        "available-hours": "u2", // 10 - 8 = 2
        "used-hours": "u8",
        "accrued-hours": "u10",
        "last-updated": expect.any(String)
      });
    });

    it("denies leave request without deducting balance", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "process-leave-request",
        ["u1", "false"], // deny
        deployer
      );
      expect(result).toBeOk(false);

      // Check request status
      const requestInfo = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-request",
        ["u1"],
        deployer
      );
      expect(requestInfo.result).toBeOk(expect.objectContaining({
        status: "u2" // denied
      }));

      // Check leave balance was NOT deducted
      const balance = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-balance",
        [`'${employee1}`, "u1"],
        deployer
      );
      expect(balance.result).toEqual({
        "available-hours": "u10", // Still 10
        "used-hours": "u0",
        "accrued-hours": "u10",
        "last-updated": expect.any(String)
      });
    });

    it("prevents non-owner from processing requests", () => {
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "process-leave-request",
        ["u1", "true"],
        employee2
      );
      expect(result).toBeErr("u100"); // ERR-NOT-AUTHORIZED
    });

    it("prevents processing already processed request", () => {
      // Process once
      simnet.callPublicFn(
        "Salary-Streaming",
        "process-leave-request",
        ["u1", "true"],
        deployer
      );

      // Try to process again
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "process-leave-request",
        ["u1", "false"],
        deployer
      );
      expect(result).toBeErr("u113"); // ERR-LEAVE-REQUEST-ALREADY-PROCESSED
    });
  });

  describe("Leave History and Tracking", () => {
    beforeEach(() => {
      simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"],
        deployer
      );
      simnet.mineEmptyBlocks(2200);
      simnet.callPublicFn(
        "Salary-Streaming",
        "accrue-leave-hours", 
        [`'${employee1}`],
        deployer
      );
    });

    it("tracks employee leave requests correctly", () => {
      // Submit multiple requests
      simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u1", "u1000", "u1008", "u4", "\"First request\""],
        employee1
      );
      simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u2", "u1100", "u1108", "u4", "\"Second request\""],
        employee1
      );

      // Check employee's request history
      const requestIds = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-employee-leave-requests",
        [`'${employee1}`],
        deployer
      );
      expect(requestIds.result).toBeOk(["u1", "u2"]);
    });

    it("provides correct leave type names", () => {
      const vacationName = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-type-name",
        ["u1"],
        deployer
      );
      expect(vacationName.result).toBeOk("\"Vacation\"");

      const sickName = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-type-name",
        ["u2"],
        deployer
      );
      expect(sickName.result).toBeOk("\"Sick\"");

      const personalName = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-type-name",
        ["u3"],
        deployer
      );
      expect(personalName.result).toBeOk("\"Personal\"");

      const invalidName = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-type-name",
        ["u4"],
        deployer
      );
      expect(invalidName.result).toBeErr("u110"); // ERR-INVALID-LEAVE-TYPE
    });
  });

  // ===========================
  // INTEGRATION TESTS
  // ===========================

  describe("Complete Employee Lifecycle", () => {
    it("handles complete employee lifecycle with leave management", () => {
      // 1. Add employee
      const addResult = simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u3000"],
        deployer
      );
      expect(addResult.result).toBeOk(true);

      // 2. Add treasury funds
      simnet.callPublicFn(
        "Salary-Streaming",
        "deposit-funds",
        ["u200000"],
        deployer
      );

      // 3. Start salary stream
      simnet.callPublicFn(
        "Salary-Streaming",
        "start-stream",
        [`'${employee1}`, "u100000", "u2000"],
        deployer
      );

      // 4. Advance time and accrue leave
      simnet.mineEmptyBlocks(2200);
      const accrualResult = simnet.callPublicFn(
        "Salary-Streaming",
        "accrue-leave-hours",
        [`'${employee1}`],
        deployer
      );
      expect(accrualResult.result).toBeOk(true);

      // 5. Submit leave request
      const leaveRequestResult = simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u1", "u2300", "u2316", "u8", "\"Well-deserved vacation\""],
        employee1
      );
      expect(leaveRequestResult.result).toBeOk("u1");

      // 6. Approve leave request
      const approvalResult = simnet.callPublicFn(
        "Salary-Streaming",
        "process-leave-request", 
        ["u1", "true"],
        deployer
      );
      expect(approvalResult.result).toBeOk(true);

      // 7. Verify final state
      const finalLeaveSummary = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-employee-leave-summary",
        [`'${employee1}`],
        deployer
      );
      expect(finalLeaveSummary.result).toBeOk(expect.objectContaining({
        vacation: expect.objectContaining({
          "available-hours": "u2", // 10 accrued - 8 used = 2
          "used-hours": "u8"
        })
      }));

      // 8. Check stream still active
      const streamInfo = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-stream-info",
        [`'${employee1}`],
        deployer
      );
      expect(streamInfo.result).toBeOk(expect.objectContaining({
        amount: "u100000",
        paused: false
      }));
    });
  });

  describe("Edge Cases and Error Handling", () => {
    it("handles maximum leave request properly", () => {
      simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"],
        deployer
      );

      // Try to request maximum allowed hours (320 = 40 days * 8 hours)
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u1", "u1000", "u1320", "u320", "\"Long leave\""],
        employee1
      );
      expect(result).toBeErr("u111"); // ERR-INSUFFICIENT-LEAVE-BALANCE (no accrued leave)
    });

    it("rejects excessive leave request", () => {
      simnet.callPublicFn(
        "Salary-Streaming",
        "add-employee",
        [`'${employee1}`, "u2500"],
        deployer
      );

      // Try to request more than maximum (321 hours)
      const { result } = simnet.callPublicFn(
        "Salary-Streaming",
        "submit-leave-request",
        ["u1", "u1000", "u1321", "u321", "\"Too long\""],
        employee1
      );
      expect(result).toBeErr("u114"); // ERR-INVALID-LEAVE-DAYS
    });

    it("handles non-existent leave request", () => {
      const { result } = simnet.callReadOnlyFn(
        "Salary-Streaming",
        "get-leave-request",
        ["u999"], // Non-existent request ID
        deployer
      );
      expect(result).toBeErr("u112"); // ERR-LEAVE-REQUEST-NOT-FOUND
    });
  });
});