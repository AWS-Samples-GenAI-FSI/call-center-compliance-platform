# Ally Compliance Test Data

## Files Created:
- `master_reference.json` - Reference data for agents, customers, states
- `sample_transcripts.txt` - Text transcripts with expected violations
- `create_test_audio.py` - Script to generate audio files
- `test_summary.json` - Generated test case summary

## Test Scenarios:

### 1. Compliant Call (A001_C001_MA_collections.wav)
- Agent: John Smith (properly identifies)
- Customer: Robert Williams (MA)
- **Expected**: No violations

### 2. Multiple Violations (A002_C002_TX_collections.wav)
- Agent: Sarah (no last name, no "AnyCompany Servicing")
- Customer: Lisa Brown (TX, cure period not expired)
- **Expected**: 4 violations (name, pre-cure payment, repo threat, garnishment)

### 3. Attorney Protected (A003_C003_CA_collections.wav)
- Customer: David Miller (attorney_retained: true)
- **Expected**: 1 violation (calling attorney-represented account)

### 4. Bankruptcy Protected (A001_C004_NY_collections.wav)
- Customer: Jennifer Davis (bankruptcy_filed: true)
- **Expected**: 1 violation (calling bankruptcy-protected account)

### 5. Massachusetts Name Rule (A002_C001_MA_collections.wav)
- Agent: "someone" (no name in MA)
- **Expected**: 1 violation (MA name requirement)

### 6. Third Party Disclosure (A001_UNKNOWN_TX_collections.wav)
- Disclosed account details to unknown person
- **Expected**: 2 violations (account disclosure, debt perception)

### 7. Do Not Call (A003_C002_TX_collections.wav)
- Customer: Lisa Brown (do_not_call: true)
- **Expected**: 1 violation (DNC violation)

### 8. Profanity (A002_C001_MA_collections.wav)
- Contains inappropriate language
- **Expected**: 1 violation (profanity)

## Usage:

1. **Generate Audio Files**:
   ```bash
   cd test-data
   python3 create_test_audio.py
   ```

2. **Upload Reference Data**:
   - Upload `master_reference.json` to S3 `reference/` folder

3. **Upload Audio Files**:
   - Upload generated `audio/*.wav` files to S3 `audio/` folder

4. **Check Results**:
   - View compliance results in React UI
   - Verify expected violations match actual results

## Expected Total Violations: 12
- 4 violations from call #2
- 1 violation each from calls #3, #4, #5, #7, #8
- 2 violations from call #6
- 0 violations from call #1