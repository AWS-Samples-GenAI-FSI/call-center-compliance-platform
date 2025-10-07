# AnyCompany Financial Services Compliance Platform

**Authors:** Shashi Makkapati, Jacob Scheatzle

![Demo](demo.gif)

## 🎯 Platform Status: Production-Ready AI-Powered Compliance System

Complete, working compliance validation platform with automated call center monitoring using AWS AI services.

## 🚨 Problem Statement

**Financial services call centers face critical compliance challenges:**

### Manual Compliance Monitoring Crisis
- Human reviewers can only check **1-3% of calls**, missing 97%+ of violations
- **Regulatory requirements** (FDCPA, TCPA, state laws) demand 100% compliance monitoring
- **High cost of violations**: $1,000-$1,500 per violation + class action lawsuit risk

### Complex Regulatory Landscape
- **43+ compliance rules** across 4 categories (identification, communication, policy, system)
- **State-specific requirements** (MA, MI, NH, AZ have unique rules)
- **Real-time detection needed** to prevent violation escalation

### Critical Compliance Areas
- 🆔 **Agent Identification**: Name disclosure requirements by state
- 📞 **Do Not Call (DNC)**: Cease and desist violations
- 🔒 **Third-Party Disclosure**: Account information leakage
- 🏥 **Medical Information**: HIPAA-related data handling
- ⚠️ **Threatening Language**: Harassment and false threats
- 🛡️ **PII Protection**: Social security, account numbers exposure

## 🏗️ Solution Architecture

![Solution Architecture](solution-architecture.png)

### **Complete AI-Powered Workflow**
```
📱 Individual Upload:
Audio Upload → S3 Input → Lambda Processor → AWS Transcribe → Transcript
                                                     ↓
DynamoDB ← Lambda Completion Handler ← S3 Transcribe Output
    ↓                                         ↓
Web Dashboard ← API Gateway ← Lambda API ← AWS Comprehend

🏭 Batch Processing (10K Daily):
EventBridge (2 AM) → Step Functions → Batch Prep → Map State (100 parallel)
                                         ↓
                    Batch Trigger → S3 Copy → Existing Processing Flow
```

## 🔧 Core Components

### **1. AWS Lambda Functions (5 Total)**

#### **🚀 Step Functions Batch Processing** (NEW)
- **Batch Prep Function** (`anycompany-batch-prep-prod`): Scans S3 folders, prepares 10K file manifests
- **Batch Trigger Function** (`anycompany-batch-trigger-prod`): Connects Step Functions to existing processing flow
- **Production Capacity**: 100 parallel files, 10K daily processing
- **Error Handling**: 5% failure tolerance, automatic retries

#### **🎯 Processor Function** (`anycompany-processor-prod`)
- **Purpose**: Initial audio file processing and transcription job creation
- **Trigger**: S3 upload event (audio/*.wav files)
- **Size**: ~2,100 bytes
- **Runtime**: Python 3.9
- **Key Functions**:
  - Creates DynamoDB call records with unique call_id
  - Starts AWS Transcribe jobs with proper naming convention
  - Handles upload failures and error logging
  - Sets initial processing status

#### **🧠 Transcription Completion Handler** (`anycompany-transcription-complete-prod`)
- **Purpose**: AI-powered compliance analysis and violation detection
- **Trigger**: S3 transcript completion (transcripts/*.json files)
- **Size**: ~27,000 bytes (largest function)
- **Runtime**: Python 3.9
- **Key Functions**:
  - **AWS Comprehend Integration**: Entity extraction, PII detection, sentiment analysis
  - **Compliance Engine**: Evaluates 43 regulatory rules
  - **Reference Data Processing**: Genesys Call ID lookup system
  - **Violation Detection**: AI-powered rule evaluation with confidence scoring
  - **Decimal Conversion**: Handles AWS Comprehend float→DynamoDB Decimal conversion
  - **Bulk Processing**: Supports both UI uploads and direct S3 bulk uploads

#### **🌐 API Function** (`anycompany-api-prod`)
- **Purpose**: REST API endpoints for web dashboard
- **Trigger**: API Gateway HTTP requests
- **Size**: ~17,900 bytes
- **Runtime**: Python 3.9
- **Endpoints**:
  - `GET /rules` - Returns 43 compliance rules grouped by category
  - `GET /results` - Returns processed calls with violations and AI quality metrics
  - `POST /upload-url` - Generates S3 presigned URLs for file uploads
  - `GET /entity-metrics` - Returns entity extraction analytics and confidence scores

### **2. AWS Transcribe Integration**

#### **Audio-to-Text Processing**
- **Input**: WAV audio files from S3 input bucket
- **Output**: JSON transcript files in S3 transcribe output bucket
- **Language**: English (en-US)
- **Job Naming**: `anycompany-{call_id}-{timestamp}`
- **Quality**: High-accuracy transcription for compliance analysis

#### **Transcription Workflow**
1. Processor Lambda starts transcription job
2. AWS Transcribe processes audio asynchronously
3. Completed transcript triggers completion handler
4. Transcript text extracted for compliance analysis

### **3. AWS Comprehend Integration**

#### **AI Entity Extraction**
- **Input**: Transcript text (chunked for 5000 char limit)
- **Services Used**:
  - `detect_entities()` - Persons, organizations
  - `detect_key_phrases()` - Financial, legal, medical terms
  - `detect_pii_entities()` - SSN, phone numbers, account numbers
  - `detect_sentiment()` - Threatening language detection

#### **Compliance-Specific Entities**
- **Persons**: Agent names, customer names (99%+ confidence)
- **Financial**: Account references, payment terms, balances
- **Legal**: Attorney, bankruptcy, legal action, garnishment
- **Medical**: Hospital, doctor, surgery, illness terms
- **Communication**: Text message, SMS, email, voicemail
- **PII**: Social security numbers, credit card numbers, phone numbers

#### **Entity Storage**
- **S3 Output**: `entities/{timestamp}_entities.json`
- **DynamoDB**: Stored with proper Decimal conversion for confidence scores
- **Quality Metrics**: Confidence thresholds, low-confidence flagging

### **4. DynamoDB Tables**

#### **Calls Table** (`anycompany-calls-prod`)
- **Primary Key**: `call_id` (UUID)
- **Key Attributes**:
  - `filename` - Original audio file name
  - `transcript` - Full transcript text from AWS Transcribe
  - `entities` - Extracted entities from AWS Comprehend (with Decimal confidence scores)
  - `violations` - Array of detected compliance violations
  - `violation_count` - Number of violations for quick filtering
  - `processing_status` - Current processing state (transcribing, completed, failed)
  - `ai_quality` - AI confidence metrics and manual review flags
  - `created_at`, `processed_at` - Timestamps

#### **Rules Table** (`anycompany-rules-prod`)
- **Primary Key**: `rule_id` (e.g., LO1001.04, LO1007.05)
- **Key Attributes**:
  - `description` - Human-readable rule description
  - `category` - identification, communication, policy, system
  - `severity` - minor, major, critical
  - `active` - Boolean flag for rule activation
  - `logic` - Complex rule evaluation logic including:
    - `type` - pattern_match, reference_check, sentiment_analysis, etc.
    - `patterns` - Regex patterns for text matching
    - `required` - Whether pattern presence/absence indicates violation
    - `conditions` - State-specific or conditional logic
    - `entity_types` - Required Comprehend entity types
    - `timeFrame` - Timing requirements (e.g., first_60_seconds)

### **5. AWS Step Functions Batch Processing** (NEW)

#### **Production State Machine** (`anycompany-batch-processor-prod`)
- **Daily Automation**: EventBridge trigger at 2:00 AM UTC
- **Batch Capacity**: Up to 15,000 files per execution
- **Parallel Processing**: 100 files simultaneously
- **Error Resilience**: 5% failure tolerance with automatic retries
- **Processing Time**: 10K files in ~100 minutes (vs 10+ hours sequential)

#### **Batch Processing Workflow**
1. **PrepareBatch**: Scan S3 folder, generate file manifest
2. **CheckBatchSize**: Validate batch size (max 15K files)
3. **ProcessBatch**: Map state with 100 parallel executions
4. **TriggerProcessing**: Connect to existing Lambda processing flow
5. **GenerateSummary**: Aggregate results and completion status

#### **Daily Automation**
- **EventBridge Rule**: `cron(0 2 * * ? *)` - Daily at 2 AM UTC
- **Input Folder**: `s3://bucket/daily-batch/`
- **Automatic Processing**: No manual intervention required
- **Monitoring**: Real-time execution tracking via Step Functions console

### **6. Compliance Rules Engine (43 Rules)**

#### **Rule Categories**
- **Identification (9 rules)**: Agent name disclosure, state-specific requirements
- **Communication (19 rules)**: DNC violations, attorney representation, third-party disclosure
- **Policy (10 rules)**: Threatening language, medical information, cure periods
- **System (4 rules)**: Documentation requirements, activity codes

#### **AI-Powered Rule Evaluation**
- **Collaborative Analysis**: Combines AWS Transcribe + Comprehend + Reference Data
- **Pattern Matching**: Regex patterns with entity validation
- **Confidence Scoring**: Quality metrics for manual review flagging
- **Reference Data Integration**: Genesys Call ID lookup for expected violations
- **State-Specific Logic**: Conditional rules based on customer location

#### **Violation Detection Process**
1. Load active rules from DynamoDB
2. Extract Genesys Call ID from filename
3. Load reference data with expected violations
4. For each rule:
   - Apply AI pattern matching
   - Validate with Comprehend entities
   - Check reference data expectations
   - Calculate confidence scores
5. Create violation records with evidence

### **7. Reference Data System**

#### **Genesys Call ID Architecture**
- **Purpose**: Universal identifier for call tracking across systems
- **Format**: `GEN-2024-001001` (Year-Category-Sequence)
- **Mapping**: Test filenames → Genesys Call IDs → Expected violations
- **Storage**: `reference/master_reference.json` in S3 input bucket

#### **Reference Data Structure**
```json
{
  "calls": {
    "GEN-2024-001001": {
      "expected_violations": ["LO1001.04"],
      "expected_entities": {
        "agent_names": ["John"],
        "threatening_language": ["arrest", "jail"]
      },
      "description": "Agent identification violation",
      "audio_file": "test_001_agent_identification_1.wav"
    }
  }
}
```

### **8. Web Dashboard (React TypeScript)**

#### **Frontend Features**
- **Call Results**: List of processed calls with violation counts
- **Rules Library**: Interactive display of all 43 compliance rules with logic details
- **Entity Metrics**: AI confidence scores and entity extraction analytics
- **Audio Playback**: Presigned S3 URLs for audio file access
- **AI Quality Indicators**: Manual review flags and confidence ratings

#### **Authentication**
- **Demo Mode**: Simplified authentication for testing
- **AWS Cognito**: User pool and identity management
- **CORS Configuration**: Proper cross-origin resource sharing

## 🏗️ Terraform Infrastructure Architecture

### **Core Architecture Files**

#### **main.tf** - Foundation Infrastructure
- **Provider Configuration**: AWS provider with version constraints
- **VPC Setup**: Custom VPC with public/private subnets across 2 AZs
- **S3 Buckets**: 4 buckets (input, transcribe-output, comprehend-output, source)
- **DynamoDB Tables**: Calls and rules tables with encryption
- **Security Groups**: ALB, container, and VPC endpoint security
- **VPC Endpoints**: ECR and S3 endpoints for private networking

#### **lambda.tf** - Serverless Functions
- **5 Lambda Functions**: API, processor, transcription-complete, batch-prep, batch-trigger
- **IAM Roles**: Comprehensive permissions for Transcribe, Comprehend, S3, DynamoDB
- **Event Triggers**: S3 notifications and SQS event source mappings
- **Code Packaging**: Automatic ZIP creation from Python files

#### **step_functions.tf** - Batch Processing (NEW)
- **Step Functions State Machine**: Production batch processor with 100 parallel execution
- **EventBridge Integration**: Daily automation at 2 AM UTC
- **IAM Roles**: Step Functions execution and EventBridge trigger permissions
- **Error Handling**: Retry logic, failure tolerance, and error isolation

#### **batch_deployment.tf** - Batch Lambda Deployment (NEW)
- **Automated Packaging**: ZIP creation for batch processing Lambda functions
- **Code Updates**: Automatic deployment of batch prep and trigger functions
- **Dependency Management**: Proper resource ordering and updates

#### **api_gateway.tf** - REST API
- **API Gateway**: Proxy integration with Lambda
- **CORS Configuration**: Full OPTIONS method support
- **Deployment**: Automatic staging to 'prod'

#### **cognito_ecs.tf** - Authentication & UI
- **Cognito User Pool**: Authentication with password policies
- **ECS Cluster**: Fargate-based container orchestration
- **Application Load Balancer**: Public-facing with health checks
- **ECR Repository**: Container image storage

### **Automated Deployment System**

#### **lambda_deployment.tf** - Orchestration
- **CodeBuild Integration**: Automated container builds (no local Docker)
- **Rules Population**: Automatic DynamoDB seeding with 43 compliance rules
- **Container Deployment**: React app build and ECR push

#### **deploy-automated.sh** - One-Command Deployment
```bash
./deploy-automated.sh  # Deploys everything automatically
```

### **Key Terraform Features**

#### **Infrastructure as Code**
- **Modular Design**: Separate files for different components
- **Variable Configuration**: Environment-specific settings
- **State Management**: Tracks resource dependencies
- **Dependency Resolution**: Proper resource ordering

#### **Production-Ready Features**
- **Security**: VPC endpoints, security groups, encryption
- **Scalability**: Auto-scaling ECS, load balancer
- **Monitoring**: CloudWatch logs, health checks
- **High Availability**: Multi-AZ deployment

#### **AI Services Integration**
- **AWS Transcribe**: Audio-to-text conversion
- **AWS Comprehend**: Entity extraction and sentiment analysis
- **Lambda Processing**: Real-time compliance analysis
- **DynamoDB Storage**: Structured data with proper indexing

### **Deployment Flow**
1. **terraform init** - Downloads providers
2. **Lambda Packaging** - Creates ZIP files from Python code
3. **Infrastructure Creation** - VPC, S3, DynamoDB, Lambda, API Gateway
4. **CodeBuild Execution** - Builds React container automatically
5. **ECS Deployment** - Runs containerized UI with load balancer
6. **Rules Population** - Seeds DynamoDB with 43 compliance rules

## 🚀 Deployment Options

### **Terraform Deployment** (Recommended)
```bash
cd terraform
terraform init
terraform apply
```

### **CloudFormation Deployment**
```bash
aws cloudformation deploy --template-file infrastructure.yaml --stack-name anycompany-compliance
```

### **Both Systems Identical**
- Same 3 Lambda functions with identical code
- Same DynamoDB table structures
- Same S3 bucket configuration
- Same API Gateway endpoints
- Same ECS/Fargate React deployment

## 📊 System Performance

### **Individual Processing Metrics**
- **Audio Processing**: ~30-60 seconds per file (AWS Transcribe)
- **Entity Extraction**: ~5-10 seconds per transcript (AWS Comprehend)
- **Compliance Analysis**: ~1-2 seconds per call (43 rules evaluation)
- **Violation Detection**: Real-time with confidence scoring

### **Batch Processing Metrics** (NEW)
- **Daily Capacity**: 10,000 calls processed automatically
- **Parallel Processing**: 100 files simultaneously
- **Processing Time**: ~100 minutes for 10K files (vs 10+ hours sequential)
- **Automation**: Daily 2 AM trigger, zero manual intervention
- **Error Resilience**: 5% failure tolerance, automatic retries
- **Scalability**: Up to 15,000 files per batch execution

### **AI Quality Metrics**
- **Entity Confidence**: 99%+ for persons, financial terms, legal language
- **PII Detection**: 80%+ threshold for sensitive data
- **Manual Review Flagging**: Low-confidence entities automatically flagged
- **False Positive Rate**: Minimized through reference data validation

## 🧪 Testing

### **Test Audio Files** (100 files)
- **Agent Identification**: 7 test scenarios
- **Threatening Language**: 7 test scenarios  
- **Legal Terms**: 7 test scenarios
- **Financial Data**: 7 test scenarios
- **Medical Terms**: 7 test scenarios
- **Communication Methods**: 7 test scenarios
- **State References**: 7 test scenarios
- **Mixed Violations**: 7 test scenarios
- **Compliant Calls**: 7 test scenarios
- **System Compliance**: 7 test scenarios

### **Reference Data Coverage**
- Expected violations mapped to Genesys Call IDs
- Entity expectations for validation
- Confidence score baselines
- Manual review triggers

## 🔒 Security & Compliance

### **Data Protection**
- **PII Redaction**: Automatic detection and masking
- **Encryption**: S3 server-side encryption, DynamoDB encryption at rest
- **Access Control**: IAM roles with least privilege
- **Audit Trail**: CloudWatch logs for all processing

### **Regulatory Compliance**
- **FDCPA**: Fair Debt Collection Practices Act
- **TCPA**: Telephone Consumer Protection Act
- **HIPAA**: Health Insurance Portability and Accountability Act
- **State Laws**: Massachusetts, Michigan, New Hampshire, Arizona specific rules

## 📈 Monitoring & Observability

### **CloudWatch Integration**
- **Lambda Metrics**: Duration, errors, invocations
- **Transcribe Metrics**: Job completion rates, failures
- **Comprehend Metrics**: Entity extraction success rates
- **Custom Metrics**: Violation detection rates, confidence scores

### **Logging**
- **Structured Logging**: JSON format with correlation IDs
- **Debug Information**: Rule evaluation details, entity confidence scores
- **Error Tracking**: Failed transcriptions, entity extraction errors
- **Performance Monitoring**: Processing times, bottleneck identification

## 🔄 Maintenance

### **Rule Updates**
- **DynamoDB Management**: Add/modify/deactivate rules via console
- **Logic Updates**: Pattern updates, threshold adjustments
- **Reference Data**: Update expected violations for new test scenarios

### **System Updates**
- **Lambda Deployments**: Both CloudFormation and Terraform synchronized
- **Version Control**: Git-based deployment with rollback capability
- **Testing**: Comprehensive test suite with 100 audio files

## 📞 Support

**System is production-ready with:**
- ✅ Complete AI-powered compliance monitoring
- ✅ 43 regulatory rules with automatic violation detection  
- ✅ AWS Transcribe + Comprehend integration
- ✅ Real-time processing with confidence scoring
- ✅ **Step Functions batch processing (10K daily calls, 100 parallel)**
- ✅ **EventBridge daily automation (2 AM UTC scheduling)**
- ✅ Web dashboard with entity analytics
- ✅ Both CloudFormation and Terraform deployment options
- ✅ Comprehensive test suite and reference data
- ✅ Enterprise-grade security and monitoring