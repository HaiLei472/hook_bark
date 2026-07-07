# AI 智能核伤功能实施计划

> **For agentic workers:** 本计划适用于 superpowers:executing-plans 或 subagent-driven-development 技能执行。步骤使用 checkbox (`- [ ]`) 语法追踪。

**Goal:** 在现有理赔系统中嵌入"AI 智能核伤"能力模块，通过 LLM + 规则引擎自动核验三方鉴定报告的伤残等级合理性，降低虚高鉴定导致的超额赔付。

**Architecture:** 三阶段流水线架构——材料结构化抽取（LLM）→ 多维校验（规则引擎 + LLM）→ 综合结论生成（LLM）。通过产险大脑平台（DeepSeek-v4）API 调用大模型，数据不出内网。

**Tech Stack:** Python 3.11+, DeepSeek-v4（产险大脑 API）, FastAPI（接口层）, Pydantic（数据模型）, pytest（测试）

## Global Constraints

- 大模型必须通过产险大脑平台 API 调用，不可直连外部模型
- 所有理赔数据不出内网
- AI 仅输出"标疑"结论，不可替代理赔员做赔付决策
- 单案件 LLM 调用次数 ≤ 5 次
- MVP 覆盖 3-5 类常见伤情类型

---

## 文件结构

```
ai-injury-review/
├── src/
│   ├── __init__.py
│   ├── models/
│   │   ├── __init__.py
│   │   └── schemas.py              # Pydantic 数据模型
│   ├── extractors/
│   │   ├── __init__.py
│   │   ├── base.py                 # 抽取器基类 + LLM调用封装
│   │   ├── report_extractor.py     # 鉴定报告抽取
│   │   └── medical_extractor.py    # 病历材料抽取
│   ├── validators/
│   │   ├── __init__.py
│   │   ├── base.py                 # 校验器基类 + 结果模型
│   │   ├── clause_matcher.py       # 条款匹配度校验
│   │   ├── metric_validator.py     # 关键数值校验
│   │   └── doc_consistency.py      # 文书一致性校验
│   ├── synthesizer/
│   │   ├── __init__.py
│   │   └── conclusion.py           # 综合结论生成
│   ├── api/
│   │   ├── __init__.py
│   │   └── model_client.py         # 产险大脑 API 客户端
│   └── pipeline.py                 # 主流程编排
├── tests/
│   ├── conftest.py                  # fixtures + mock 数据
│   ├── test_extractors.py
│   ├── test_validators.py
│   ├── test_synthesizer.py
│   └── test_pipeline.py
├── evaluation/
│   ├── sample_cases.json            # 样本案件数据（脱敏）
│   └── benchmark.py                 # 回溯测试脚本
├── data/
│   └── disability_standard.json     # 人体损伤致残程度分级 条款结构化数据
├── prompts/
│   ├── report_extraction.txt        # 鉴定报告抽取 prompt 模板
│   ├── medical_extraction.txt       # 病历抽取 prompt 模板
│   ├── clause_match.txt             # 条款匹配度判断 prompt 模板
│   └── conclusion.txt               # 综合结论生成 prompt 模板
├── requirements.txt
└── README.md
```

**职责划分：**
- `models/` — 全部数据结构定义，零业务逻辑，所有模块引用此处类型
- `extractors/` — 只负责从非结构化文本中抽取 JSON，不做校验
- `validators/` — 只接收结构化数据做校验，不调 LLM（条款匹配度除外）
- `synthesizer/` — 只接收校验结果生成结论，不直接访问原始材料
- `api/` — 单点封装所有产险大脑 API 调用，统一处理重试/超时/限流
- `pipeline.py` — 编排上述模块，是外部调用唯一入口

---

### Task 1: 数据模型定义

**Files:**
- Create: `src/models/__init__.py`
- Create: `src/models/schemas.py`

**Interfaces:**
- Produces: 所有后续任务引用这些类型

- [ ] **Step 1: 定义全部 Pydantic 数据模型**

```python
# src/models/schemas.py
from pydantic import BaseModel
from typing import Optional
from enum import Enum
from datetime import date


# ── 原始输入 ──
class CaseInput(BaseModel):
    """单案件输入——所有原始材料文本"""
    case_id: str
    report_text: str       # 鉴定报告全文（OCR后）
    medical_text: str      # 全部病历材料合并文本


# ── 抽取结果 ──
class ReportExtraction(BaseModel):
    """鉴定报告结构化抽取结果"""
    claimant_name: str
    claimant_age: int
    claimant_gender: str
    injury_cause: str              # 受伤原因（交通事故描述）
    injury_body_parts: list[str]   # 受伤部位
    injury_date: Optional[date]
    assessment_date: Optional[date]
    disability_level: int           # 1-10
    applied_clause_code: str        # 引用的《人体损伤致残程度分级》条款编号，如 "5.9.6.1"
    applied_clause_text: str        # 条款原文
    joint_rom_values: dict[str, float]     # { "左膝关节屈曲": 45.0, ... }
    muscle_strength_values: dict[str, int] # { "左上肢近端": 4, ... }
    imaging_findings: str           # 鉴定报告中引用的影像学发现


class MedicalExtraction(BaseModel):
    """病历材料结构化抽取结果"""
    admission_diagnosis: list[str]
    discharge_diagnosis: list[str]
    surgeries: list[str]            # 手术名称列表
    imaging_reports: str            # 影像报告关键描述汇总
    discharge_function_status: str  # 出院时功能恢复情况
    discharge_instructions: str     # 医嘱
    in_hospital_days: Optional[int]


class ExtractionResult(BaseModel):
    """阶段一输出"""
    case_id: str
    report: ReportExtraction
    medical: MedicalExtraction


# ── 校验结果 ──
class RiskLevel(str, Enum):
    GREEN = "green"
    YELLOW = "yellow"
    RED = "red"


class ValidationItem(BaseModel):
    """单条校验发现"""
    dimension: str          # "clause_match" | "metric" | "doc_consistency"
    risk: RiskLevel
    title: str              # 简短标题
    detail: str             # 详细说明（"问题 + 依据"）
    source_quote: str | None = None  # 材料原文摘引


class ValidationResult(BaseModel):
    """阶段二输出"""
    case_id: str
    items: list[ValidationItem]

    @property
    def red_count(self) -> int:
        return sum(1 for i in self.items if i.risk == RiskLevel.RED)

    @property
    def yellow_count(self) -> int:
        return sum(1 for i in self.items if i.risk == RiskLevel.YELLOW)


# ── 综合结论 ──
class ReviewConclusion(BaseModel):
    """阶段三输出——最终审核结论"""
    case_id: str
    risk_score: int                      # 0-100
    risk_level: str                      # "low" | "medium" | "high"
    abnormal_items: list[ValidationItem]  # 红/黄标的异常项
    summary: str                          # 理赔员可读的审核摘要
    suggestion: str                       # "通过" | "退回鉴定机构要求说明" | "启动调查流程"
    extraction: ExtractionResult          # 附带抽取结果供理赔员参考
```

- [ ] **Step 2: 运行类型检查验证模型无语法错误**

```bash
cd src && python -c "from models.schemas import CaseInput, ExtractionResult, ValidationResult, ReviewConclusion; print('OK')"
```

- [ ] **Step 3: Commit**

```bash
git add src/models/
git commit -m "feat: define Pydantic data models for AI 智能核伤 pipeline"
```

---

### Task 2: 产险大脑 API 客户端

**Files:**
- Create: `src/api/__init__.py`
- Create: `src/api/model_client.py`
- Create: `tests/conftest.py`

**Interfaces:**
- Produces:
  - `ModelClient.chat(prompt: str, system_prompt: str = None, temperature: float = 0.1) -> str`
  - `ModelClient.chat_json(prompt: str, system_prompt: str = None, json_schema: dict = None) -> dict`

- [ ] **Step 1: 编写 API 客户端测试**

```python
# tests/conftest.py
import pytest
from unittest.mock import patch, MagicMock


@pytest.fixture
def sample_case() -> dict:
    """标准测试用案件——膝关节损伤评为9级"""
    return {
        "case_id": "CASE-2026-001",
        "report_text": """
        伤者：张某某，男，45岁
        受伤原因：2025年8月15日发生交通事故，致左膝关节损伤
        鉴定日期：2026年2月20日
        伤残等级：九级
        依据条款：依据《人体损伤致残程度分级》第5.9.6.1条"一上肢或一下肢三大关节功能丧失50%以上"
        检查所见：左膝关节主动屈曲45°，伸直0°，关节活动度丧失约65%
        影像学：左膝MRI示内侧半月板后角III度损伤，前交叉韧带部分撕裂
        """,
        "medical_text": """
        入院日期：2025-08-15
        出院日期：2025-08-28
        入院诊断：1.左膝关节外伤 2.左膝内侧半月板损伤
        出院诊断：1.左膝内侧半月板后角损伤（III度）2.左膝前交叉韧带部分撕裂
        手术记录：2025-08-18行左膝关节镜下内侧半月板缝合术
        出院情况：左膝关节轻度肿胀，主动屈曲可达80°，伸直0°
        医嘱：继续康复训练，定期复查
        """
    }


@pytest.fixture
def mock_model_response():
    """Mock 产险大脑 API 返回"""
    return {
        "choices": [{
            "message": {
                "content": '{"claimant_name":"张某某","claimant_age":45,"disability_level":9}'
            }
        }]
    }
```

```python
# tests/test_api_client.py (将在 test_extractors 中引用)
import pytest
from src.api.model_client import ModelClient


class TestModelClient:
    def test_chat_returns_string(self):
        """未 mock 时的连通性测试——需产险大脑环境，CI 中 skip"""
        pytest.skip("Requires 产险大脑 connectivity")
        client = ModelClient()
        result = client.chat("回复'OK'")
        assert isinstance(result, str)
        assert len(result) > 0

    def test_chat_json_parses_response(self):
        pytest.skip("Requires 产险大脑 connectivity")
        client = ModelClient()
        result = client.chat_json(
            '回复JSON: {"status":"ok"}',
            system_prompt="你只回复JSON"
        )
        assert result["status"] == "ok"
```

- [ ] **Step 2: 实现 API 客户端**

```python
# src/api/model_client.py
import json
import time
import requests
from typing import Optional


class ModelClient:
    """产险大脑 DeepSeek-v4 API 客户端"""

    def __init__(
        self,
        base_url: str = "http://chanxian-brain.internal/api/v1",
        api_key: str | None = None,
        model: str = "deepseek-v4",
        max_retries: int = 3,
        timeout: int = 60
    ):
        self.base_url = base_url
        self.api_key = api_key
        self.model = model
        self.max_retries = max_retries
        self.timeout = timeout

    def _call(self, messages: list[dict], temperature: float = 0.1) -> str:
        """底层 API 调用，含重试逻辑"""
        last_error = None
        for attempt in range(self.max_retries):
            try:
                resp = requests.post(
                    f"{self.base_url}/chat/completions",
                    json={
                        "model": self.model,
                        "messages": messages,
                        "temperature": temperature,
                    },
                    headers={"Authorization": f"Bearer {self.api_key}"} if self.api_key else {},
                    timeout=self.timeout,
                )
                resp.raise_for_status()
                return resp.json()["choices"][0]["message"]["content"]
            except requests.RequestException as e:
                last_error = e
                if attempt < self.max_retries - 1:
                    time.sleep(2 ** attempt)
        raise last_error

    def chat(
        self,
        prompt: str,
        system_prompt: str | None = None,
        temperature: float = 0.1
    ) -> str:
        """单轮对话"""
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})
        return self._call(messages, temperature)

    def chat_json(
        self,
        prompt: str,
        system_prompt: str | None = None
    ) -> dict:
        """返回 JSON 解析结果，失败抛异常"""
        raw = self.chat(prompt, system_prompt, temperature=0.0)
        # 处理模型可能在 JSON 外包裹 ```json ... ``` 的情况
        raw = raw.strip()
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1]
            if raw.endswith("```"):
                raw = raw[:-3]
        return json.loads(raw)
```

- [ ] **Step 3: 验证导入和基本功能**

```bash
cd src && python -c "from api.model_client import ModelClient; c = ModelClient(); print('OK')"
```

- [ ] **Step 4: Commit**

```bash
git add src/api/ tests/conftest.py
git commit -m "feat: add 产险大脑 DeepSeek-v4 API client with retry logic"
```

---

### Task 3: 材料抽取器

**Files:**
- Create: `src/extractors/__init__.py`
- Create: `src/extractors/base.py`
- Create: `src/extractors/report_extractor.py`
- Create: `src/extractors/medical_extractor.py`
- Create: `prompts/report_extraction.txt`
- Create: `prompts/medical_extraction.txt`
- Create: `tests/test_extractors.py`

**Interfaces:**
- Consumes: `ModelClient.chat_json()` (Task 2), `CaseInput`, `ExtractionResult`, `ReportExtraction`, `MedicalExtraction` (Task 1)
- Produces:
  - `ReportExtractor.extract(case_input: CaseInput) -> ReportExtraction`
  - `MedicalExtractor.extract(case_input: CaseInput) -> MedicalExtraction`

- [ ] **Step 1: 编写抽取器基类**

```python
# src/extractors/base.py
from src.api.model_client import ModelClient
from src.models.schemas import ExtractionResult
import json


class BaseExtractor:
    """抽取器基类——封装 LLM 调用的通用逻辑"""

    def __init__(self, client: ModelClient):
        self.client = client

    def _extract_json(self, prompt: str, system_prompt: str) -> dict:
        """调用 LLM 并返回 JSON"""
        return self.client.chat_json(prompt, system_prompt)
```

- [ ] **Step 2: 编写 prompt 模板**

```text
# prompts/report_extraction.txt
你是一位专业的保险理赔审核专家。请从以下《伤残鉴定报告》中抽取关键信息。

## 抽取要求
1. 如果某个字段在报告中未提及，填写 null
2. 关节活动度数值必须精确（从报告中摘录具体度数）
3. 条款编号和条款原文必须原文照抄，不要改写
4. 返回严格的 JSON 格式

## 报告内容
{report_text}

## 输出 JSON Schema
{{
    "claimant_name": "伤者姓名",
    "claimant_age": 年龄数字,
    "claimant_gender": "男/女",
    "injury_cause": "受伤原因描述",
    "injury_body_parts": ["部位1", "部位2"],
    "injury_date": "YYYY-MM-DD 或 null",
    "assessment_date": "YYYY-MM-DD 或 null",
    "disability_level": 等级数字(1-10),
    "applied_clause_code": "如 5.9.6.1",
    "applied_clause_text": "条款原文",
    "joint_rom_values": {{"关节名": 度数值}},
    "muscle_strength_values": {{"肌群名": 级数}},
    "imaging_findings": "影像学发现描述或null"
}}
```

```text
# prompts/medical_extraction.txt
你是一位专业的医学文书审核专家。请从以下病历材料中抽取关键信息。

## 抽取要求
1. 出院诊断比入院诊断更重要，两者都要抽取
2. 影像报告只抽取关键阳性发现，忽略正常描述
3. 如果某个字段在病历中未提及，填写 null
4. 返回严格的 JSON 格式

## 病历内容
{medical_text}

## 输出 JSON Schema
{{
    "admission_diagnosis": ["诊断1", "诊断2"],
    "discharge_diagnosis": ["诊断1", "诊断2"],
    "surgeries": ["手术名称1"],
    "imaging_reports": "影像发现汇总",
    "discharge_function_status": "出院时功能状态描述",
    "discharge_instructions": "医嘱内容",
    "in_hospital_days": 天数或null
}}
```

- [ ] **Step 3: 编写抽取器测试**

```python
# tests/test_extractors.py
import pytest
from unittest.mock import MagicMock
from src.extractors.report_extractor import ReportExtractor
from src.extractors.medical_extractor import MedicalExtractor
from src.models.schemas import CaseInput


class TestReportExtractor:
    def test_extract_joint_rom_from_report(self, sample_case):
        """验证从鉴定报告抽取关节活动度数值"""
        mock_client = MagicMock()
        mock_client.chat_json.return_value = {
            "claimant_name": "张某某",
            "claimant_age": 45,
            "claimant_gender": "男",
            "injury_cause": "交通事故",
            "injury_body_parts": ["左膝关节"],
            "injury_date": "2025-08-15",
            "assessment_date": "2026-02-20",
            "disability_level": 9,
            "applied_clause_code": "5.9.6.1",
            "applied_clause_text": "一上肢或一下肢三大关节功能丧失50%以上",
            "joint_rom_values": {"左膝关节屈曲": 45.0},
            "muscle_strength_values": {},
            "imaging_findings": "左膝MRI示内侧半月板后角III度损伤"
        }

        extractor = ReportExtractor(mock_client)
        case = CaseInput(
            case_id="CASE-001",
            report_text=sample_case["report_text"],
            medical_text=sample_case["medical_text"]
        )
        result = extractor.extract(case)

        assert result.disability_level == 9
        assert result.applied_clause_code == "5.9.6.1"
        assert result.joint_rom_values["左膝关节屈曲"] == 45.0


class TestMedicalExtractor:
    def test_extract_surgery_from_medical(self, sample_case):
        """验证从病历抽取手术记录"""
        mock_client = MagicMock()
        mock_client.chat_json.return_value = {
            "admission_diagnosis": ["左膝关节外伤", "左膝内侧半月板损伤"],
            "discharge_diagnosis": ["左膝内侧半月板后角损伤（III度）", "左膝前交叉韧带部分撕裂"],
            "surgeries": ["左膝关节镜下内侧半月板缝合术"],
            "imaging_reports": "左膝MRI示内侧半月板后角III度损伤",
            "discharge_function_status": "左膝关节轻度肿胀，主动屈曲可达80°",
            "discharge_instructions": "继续康复训练，定期复查",
            "in_hospital_days": 13
        }

        extractor = MedicalExtractor(mock_client)
        case = CaseInput(
            case_id="CASE-001",
            report_text="",
            medical_text=sample_case["medical_text"]
        )
        result = extractor.extract(case)

        assert len(result.surgeries) == 1
        assert "半月板缝合术" in result.surgeries[0]
        assert "屈曲可达80°" in result.discharge_function_status
```

- [ ] **Step 4: 实现抽取器**

```python
# src/extractors/report_extractor.py
from pathlib import Path
from src.extractors.base import BaseExtractor
from src.models.schemas import CaseInput, ReportExtraction

PROMPT_DIR = Path(__file__).parent.parent.parent / "prompts"


class ReportExtractor(BaseExtractor):
    """从鉴定报告中抽取结构化字段"""

    def __init__(self, client):
        super().__init__(client)
        self._template = (PROMPT_DIR / "report_extraction.txt").read_text()

    def extract(self, case: CaseInput) -> ReportExtraction:
        prompt = self._template.format(report_text=case.report_text)
        data = self._extract_json(prompt, "你只返回JSON，不要其他内容。")
        return ReportExtraction(**data)
```

```python
# src/extractors/medical_extractor.py
from pathlib import Path
from src.extractors.base import BaseExtractor
from src.models.schemas import CaseInput, MedicalExtraction

PROMPT_DIR = Path(__file__).parent.parent.parent / "prompts"


class MedicalExtractor(BaseExtractor):
    """从病历材料中抽取结构化字段"""

    def __init__(self, client):
        super().__init__(client)
        self._template = (PROMPT_DIR / "medical_extraction.txt").read_text()

    def extract(self, case: CaseInput) -> MedicalExtraction:
        prompt = self._template.format(medical_text=case.medical_text)
        data = self._extract_json(prompt, "你只返回JSON，不要其他内容。")
        return MedicalExtraction(**data)
```

- [ ] **Step 5: 运行测试并提交**

```bash
pytest tests/test_extractors.py -v
```

```bash
git add src/extractors/ prompts/ tests/test_extractors.py
git commit -m "feat: add report and medical record extractors with prompt templates"
```

---

### Task 4: 多维校验器

**Files:**
- Create: `src/validators/__init__.py`
- Create: `src/validators/base.py`
- Create: `src/validators/clause_matcher.py`
- Create: `src/validators/metric_validator.py`
- Create: `src/validators/doc_consistency.py`
- Create: `prompts/clause_match.txt`
- Create: `data/disability_standard.json`
- Create: `tests/test_validators.py`

**Interfaces:**
- Consumes: `ExtractionResult` (Task 1), `ModelClient.chat_json()` (Task 2, 仅 clause_matcher 使用)
- Produces: `ValidationResult`, `ValidationItem`, 各校验器返回 `list[ValidationItem]`

- [ ] **Step 1: 编写校验器基类**

```python
# src/validators/base.py
from abc import ABC, abstractmethod
from src.models.schemas import ExtractionResult, ValidationItem


class BaseValidator(ABC):
    """校验器基类"""

    @abstractmethod
    def validate(self, extraction: ExtractionResult) -> list[ValidationItem]:
        """返回发现的异常项列表，空列表表示全部通过"""
        ...
```

- [ ] **Step 2: 编写条款匹配度校验器测试**

```python
# tests/test_validators.py
import pytest
from unittest.mock import MagicMock
from src.validators.clause_matcher import ClauseMatcher
from src.validators.metric_validator import MetricValidator
from src.validators.doc_consistency import DocConsistencyValidator
from src.models.schemas import (
    ExtractionResult, ReportExtraction, MedicalExtraction, RiskLevel
)


@pytest.fixture
def matching_extraction() -> ExtractionResult:
    """伤情与条款匹配的案件"""
    return ExtractionResult(
        case_id="CASE-001",
        report=ReportExtraction(
            claimant_name="张某某", claimant_age=45, claimant_gender="男",
            injury_cause="交通事故",
            injury_body_parts=["左膝关节"],
            injury_date="2025-08-15",
            assessment_date="2026-02-20",
            disability_level=9,
            applied_clause_code="5.9.6.1",
            applied_clause_text="一上肢或一下肢三大关节功能丧失50%以上",
            joint_rom_values={"左膝关节屈曲": 45.0},
            muscle_strength_values={},
            imaging_findings="左膝半月板III度损伤，前交叉韧带撕裂"
        ),
        medical=MedicalExtraction(
            admission_diagnosis=["左膝关节外伤"],
            discharge_diagnosis=["左膝内侧半月板后角损伤（III度）", "左膝前交叉韧带部分撕裂"],
            surgeries=["关节镜下内侧半月板缝合术"],
            imaging_reports="MRI示内侧半月板后角III度损伤，前交叉韧带部分撕裂",
            discharge_function_status="主动屈曲可达80°",
            discharge_instructions="继续康复训练",
            in_hospital_days=13
        )
    )


@pytest.fixture
def mismatched_extraction() -> ExtractionResult:
    """伤情与条款不匹配的案件——软组织挫伤评为关节功能丧失"""
    return ExtractionResult(
        case_id="CASE-002",
        report=ReportExtraction(
            claimant_name="李某某", claimant_age=32, claimant_gender="女",
            injury_cause="交通事故",
            injury_body_parts=["左肩"],
            injury_date="2025-10-01",
            assessment_date="2025-12-15",
            disability_level=9,
            applied_clause_code="5.9.6.1",
            applied_clause_text="一上肢或一下肢三大关节功能丧失50%以上",
            joint_rom_values={"左肩关节前屈": 50.0},
            muscle_strength_values={},
            imaging_findings="左肩关节未见明显异常"
        ),
        medical=MedicalExtraction(
            admission_diagnosis=["左肩部软组织挫伤"],
            discharge_diagnosis=["左肩部软组织挫伤"],
            surgeries=[],
            imaging_reports="X线片未见骨折，超声未见肩袖撕裂",
            discharge_function_status="左肩活动自如",
            discharge_instructions="无特殊",
            in_hospital_days=3
        )
    )


class TestClauseMatcher:
    def test_matching_case_passes(self, matching_extraction):
        mock_client = MagicMock()
        mock_client.chat_json.return_value = {
            "is_match": True,
            "reasoning": "病历明确显示半月板III度损伤和韧带撕裂，属于膝关节结构损伤，引用条款正确"
        }
        validator = ClauseMatcher(mock_client)
        items = validator.validate(matching_extraction)
        assert all(i.risk != RiskLevel.RED for i in items)

    def test_mismatched_case_flags_red(self, mismatched_extraction):
        mock_client = MagicMock()
        mock_client.chat_json.return_value = {
            "is_match": False,
            "reasoning": "病历诊断为软组织挫伤，无关节结构损伤，不符合'关节功能丧失50%以上'所要求的器质性基础"
        }
        validator = ClauseMatcher(mock_client)
        items = validator.validate(mismatched_extraction)
        assert any(i.risk == RiskLevel.RED for i in items)
        assert any("软组织挫伤" in i.detail for i in items)
```

- [ ] **Step 3: 实现条款匹配度校验器**

```python
# src/validators/clause_matcher.py
from pathlib import Path
from src.api.model_client import ModelClient
from src.validators.base import BaseValidator
from src.models.schemas import ExtractionResult, ValidationItem, RiskLevel

PROMPT_DIR = Path(__file__).parent.parent.parent / "prompts"


class ClauseMatcher(BaseValidator):
    """校验鉴定报告引用的伤残条款是否与病历诊断匹配"""

    def __init__(self, client: ModelClient):
        self.client = client
        self._template = (PROMPT_DIR / "clause_match.txt").read_text()

    def validate(self, extraction: ExtractionResult) -> list[ValidationItem]:
        report = extraction.report
        medical = extraction.medical

        prompt = self._template.format(
            applied_clause_code=report.applied_clause_code,
            applied_clause_text=report.applied_clause_text,
            disability_level=report.disability_level,
            discharge_diagnosis="；".join(medical.discharge_diagnosis),
            surgeries="；".join(medical.surgeries) if medical.surgeries else "无",
            imaging_reports=medical.imaging_reports,
            discharge_function_status=medical.discharge_function_status,
            report_joint_rom=str(report.joint_rom_values),
            report_imaging=report.imaging_findings or "无"
        )

        result = self.client.chat_json(
            prompt,
            system_prompt="你是《人体损伤致残程度分级》鉴定标准的审核专家，只返回JSON。"
        )

        if result.get("is_match", True):
            return []
        else:
            return [ValidationItem(
                dimension="clause_match",
                risk=RiskLevel.RED,
                title="伤残等级与伤情基础不匹配",
                detail=f"鉴定引用条款 {report.applied_clause_code}，但病历诊断为{';'.join(medical.discharge_diagnosis)}。{result.get('reasoning', '')}",
                source_quote=report.applied_clause_text
            )]
```

```text
# prompts/clause_match.txt
你是一位《人体损伤致残程度分级》鉴定标准的审核专家。请判断以下案件中，病历诊断的伤情基础是否能支撑鉴定报告所引用的伤残条款。

## 鉴定报告信息
- 评定伤残等级：{disability_level}级
- 引用条款编号：{applied_clause_code}
- 引用条款原文：{applied_clause_text}
- 鉴定报告记载的关节活动度：{report_joint_rom}
- 鉴定报告引用的影像学发现：{report_imaging}

## 病历信息
- 出院诊断：{discharge_diagnosis}
- 手术记录：{surgeries}
- 影像报告：{imaging_reports}
- 出院功能状态：{discharge_function_status}

## 判断标准
- 条款要求的损伤类型（如关节结构损伤、骨折、神经损伤等）是否在病历诊断中明确存在？
- 如果病历仅为软组织挫伤、扭伤等轻微损伤，不应匹配需要器质性损伤基础的条款
- 注意：即使临床表现有关节活动受限，如果没有对应的器质性损伤诊断，也不应直接匹配

请返回JSON：
{{"is_match": true/false, "reasoning": "简要说明匹配或不匹配的理由"}}
```

- [ ] **Step 4: 实现关键数值校验器**

```python
# src/validators/metric_validator.py
from src.validators.base import BaseValidator
from src.models.schemas import ExtractionResult, ValidationItem, RiskLevel


class MetricValidator(BaseValidator):
    """关键临床指标数值对比校验——纯规则引擎"""

    ROM_DIFF_THRESHOLD = 15.0   # 关节活动度差异超过15°标红
    ROM_WARN_THRESHOLD = 10.0   # 超过10°标黄

    STRENGTH_DIFF_THRESHOLD = 1  # 肌力差1级以上标红

    def validate(self, extraction: ExtractionResult) -> list[ValidationItem]:
        items = []
        report = extraction.report
        medical = extraction.medical

        # 校验关节活动度
        # 从出院功能描述中尝试提取数值
        discharge_rom = self._parse_rom_from_text(medical.discharge_function_status)

        for joint_name, report_rom in report.joint_rom_values.items():
            if joint_name in discharge_rom:
                diff = abs(report_rom - discharge_rom[joint_name])
                if diff > self.ROM_DIFF_THRESHOLD:
                    items.append(ValidationItem(
                        dimension="metric",
                        risk=RiskLevel.RED,
                        title=f"{joint_name}活动度数值不一致",
                        detail=f"鉴定报告测量{report_rom}°，出院记录记载约{discharge_rom[joint_name]}°，差值{diff}°超过阈值{self.ROM_DIFF_THRESHOLD}°",
                        source_quote=f"鉴定报告：{report_rom}°"
                    ))
                elif diff > self.ROM_WARN_THRESHOLD:
                    items.append(ValidationItem(
                        dimension="metric",
                        risk=RiskLevel.YELLOW,
                        title=f"{joint_name}活动度数值略有偏差",
                        detail=f"鉴定报告{report_rom}° vs 出院记录约{discharge_rom[joint_name]}°，差值{diff}°",
                        source_quote=f"鉴定报告：{report_rom}°"
                    ))

        # 校验肌力等级
        for muscle_name, report_strength in report.muscle_strength_values.items():
            discharge_strength = self._parse_strength_from_text(
                medical.discharge_function_status + medical.discharge_instructions
            )
            if muscle_name in discharge_strength:
                diff = abs(report_strength - discharge_strength[muscle_name])
                if diff >= self.STRENGTH_DIFF_THRESHOLD:
                    items.append(ValidationItem(
                        dimension="metric",
                        risk=RiskLevel.RED,
                        title=f"{muscle_name}肌力等级不一致",
                        detail=f"鉴定报告{report_strength}级 vs 出院记录{discharge_strength[muscle_name]}级，差{diff}级",
                        source_quote=f"鉴定报告：{report_strength}级"
                    ))

        return items

    @staticmethod
    def _parse_rom_from_text(text: str) -> dict[str, float]:
        """从文本中解析关节活动度数值——简单正则匹配"""
        import re
        result = {}
        # 匹配模式: "XX关节屈曲NN°" 等
        patterns = [
            r'(?P<joint>\S+?(?:关节)?)(?:主动|被动)?屈曲.*?(?P<deg>\d+)°',
            r'(?P<joint>\S+?(?:关节)?)(?:主动|被动)?伸展.*?(?P<deg>\d+)°',
            r'屈曲[可]?[达]?(?P<deg>\d+)°',
        ]
        for pattern in patterns:
            for m in re.finditer(pattern, text):
                joint = m.group('joint') if 'joint' in m.groupdict() and m.group('joint') else "关节"
                deg = int(m.group('deg'))
                result[joint] = float(deg)
        return result

    @staticmethod
    def _parse_strength_from_text(text: str) -> dict[str, int]:
        """从文本中解析肌力等级"""
        import re
        result = {}
        pattern = r'(?P<muscle>\S+?(?:肌群|肌力)?)\s*[：:]*\s*(?P<grade>[0-5])级'
        for m in re.finditer(pattern, text):
            result[m.group('muscle')] = int(m.group('grade'))
        return result
```

- [ ] **Step 5: 实现文书一致性校验器**

```python
# src/validators/doc_consistency.py
from src.validators.base import BaseValidator
from src.models.schemas import ExtractionResult, ValidationItem, RiskLevel


class DocConsistencyValidator(BaseValidator):
    """校验鉴定报告与病历的文书信息一致性——纯规则引擎"""

    def validate(self, extraction: ExtractionResult) -> list[ValidationItem]:
        items = []
        report = extraction.report
        medical = extraction.medical

        # 校验伤者姓名一致
        # 实际场景中由上游系统传入，此处为接口占位
        # 校验受伤原因关键词匹配
        if report.injury_cause and medical.discharge_diagnosis:
            cause_keywords = {"交通事故", "车祸", "碰撞", "摔伤", "坠落", "砸伤", "挤压"}
            has_cause_match = any(
                kw in report.injury_cause for kw in cause_keywords
            )
            if not has_cause_match:
                # 受伤原因与诊断性质的一致性判断
                # 如果诊断是骨折但原因文中无外伤相关描述
                fracture_keywords = {"骨折", "骨裂", "断裂", "撕裂", "损伤"}
                has_fracture_diag = any(
                    any(kw in diag for kw in fracture_keywords)
                    for diag in medical.discharge_diagnosis
                )
                if has_fracture_diag:
                    items.append(ValidationItem(
                        dimension="doc_consistency",
                        risk=RiskLevel.YELLOW,
                        title="受伤原因描述与伤情不匹配",
                        detail=f"病历诊断包含器质性损伤，但鉴定报告中受伤原因描述可能不完整",
                        source_quote=report.injury_cause
                    ))

        # 校验受伤部位一致性
        report_parts_lower = {p.lower() for p in report.injury_body_parts}
        all_diag_text = " ".join(
            medical.admission_diagnosis + medical.discharge_diagnosis
        ).lower()

        for part in report_parts_lower:
            if part not in all_diag_text:
                items.append(ValidationItem(
                    dimension="doc_consistency",
                    risk=RiskLevel.YELLOW,
                    title=f"受伤部位描述不完全一致",
                    detail=f"鉴定报告记录受伤部位含'{part}'，但病历诊断中未明确对应",
                    source_quote=None
                ))

        return items
```

- [ ] **Step 6: 运行测试并提交**

```bash
pytest tests/test_validators.py -v
```

```bash
git add src/validators/ prompts/clause_match.txt tests/test_validators.py
git commit -m "feat: add multi-dimension validators for clause match, metrics, and doc consistency"
```

---

### Task 5: 综合结论生成器

**Files:**
- Create: `src/synthesizer/__init__.py`
- Create: `src/synthesizer/conclusion.py`
- Create: `prompts/conclusion.txt`
- Create: `tests/test_synthesizer.py`

**Interfaces:**
- Consumes: `ValidationResult` (Task 1), `ExtractionResult` (Task 1), `ModelClient.chat()` (Task 2)
- Produces: `ReviewConclusion`

- [ ] **Step 1: 编写综合结论 prompt 模板**

```text
# prompts/conclusion.txt
你是一位车险人伤理赔审核专家。请根据AI系统对鉴定报告的多维校验结果，生成理赔员可读的审核摘要。

## 案件信息
- 评定伤残等级：{disability_level}级
- 引用条款：{clause_code} {clause_text}
- 出院诊断：{discharge_diagnosis}

## 校验发现
{validation_summary}

## 要求
1. 用通俗语言总结核心风险点，不超过150字
2. 给出风险评级：低/中/高
3. 给出建议操作：通过 / 退回鉴定机构要求说明 / 启动调查流程

返回JSON：
{{
    "summary": "审核摘要，用理赔员能理解的语言",
    "risk_level": "low/medium/high",
    "suggestion": "通过/退回鉴定机构要求说明/启动调查流程"
}}
```

- [ ] **Step 2: 编写结论生成器测试**

```python
# tests/test_synthesizer.py
import pytest
from unittest.mock import MagicMock
from src.synthesizer.conclusion import ConclusionSynthesizer
from src.models.schemas import (
    ExtractionResult, ValidationResult, ValidationItem, RiskLevel,
    ReportExtraction, MedicalExtraction
)


@pytest.fixture
def high_risk_validation() -> tuple[ExtractionResult, ValidationResult]:
    extraction = ExtractionResult(
        case_id="CASE-002",
        report=ReportExtraction(
            claimant_name="李某某", claimant_age=32, claimant_gender="女",
            injury_cause="交通事故", injury_body_parts=["左肩"],
            injury_date="2025-10-01", assessment_date="2025-12-15",
            disability_level=9, applied_clause_code="5.9.6.1",
            applied_clause_text="一上肢或一下肢三大关节功能丧失50%以上",
            joint_rom_values={"左肩关节前屈": 50.0},
            muscle_strength_values={}, imaging_findings="未见异常"
        ),
        medical=MedicalExtraction(
            admission_diagnosis=["左肩部软组织挫伤"],
            discharge_diagnosis=["左肩部软组织挫伤"],
            surgeries=[], imaging_reports="未见骨折",
            discharge_function_status="活动自如",
            discharge_instructions="无特殊", in_hospital_days=3
        )
    )
    validation = ValidationResult(
        case_id="CASE-002",
        items=[
            ValidationItem(
                dimension="clause_match", risk=RiskLevel.RED,
                title="伤残等级与伤情基础不匹配",
                detail="病历为软组织挫伤，不符合关节功能丧失条款",
                source_quote="5.9.6.1"
            ),
            ValidationItem(
                dimension="metric", risk=RiskLevel.RED,
                title="左肩关节活动度数值不一致",
                detail="鉴定报告50° vs 出院活动自如，严重不一致",
                source_quote="鉴定报告：50°"
            )
        ]
    )
    return extraction, validation


class TestConclusionSynthesizer:
    def test_high_risk_case_returns_high_risk(self, high_risk_validation):
        extraction, validation = high_risk_validation
        mock_client = MagicMock()
        mock_client.chat_json.return_value = {
            "summary": "鉴定报告评定9级与病历诊断严重不符，建议调查",
            "risk_level": "high",
            "suggestion": "启动调查流程"
        }

        synthesizer = ConclusionSynthesizer(mock_client)
        result = synthesizer.synthesize(extraction, validation)

        assert result.risk_score >= 60
        assert result.risk_level == "high"
        assert result.suggestion == "启动调查流程"

    def test_risk_score_calculation(self, high_risk_validation):
        """验证风险评分计算逻辑——2红应≥60分"""
        extraction, validation = high_risk_validation
        mock_client = MagicMock()
        mock_client.chat_json.return_value = {
            "summary": "test", "risk_level": "high",
            "suggestion": "启动调查流程"
        }

        synthesizer = ConclusionSynthesizer(mock_client)
        result = synthesizer.synthesize(extraction, validation)

        # 2个红色 → 基础分 40 + 2×20 = 80，上限 100
        assert 60 <= result.risk_score <= 100
```

- [ ] **Step 3: 实现结论生成器**

```python
# src/synthesizer/conclusion.py
from pathlib import Path
from src.api.model_client import ModelClient
from src.models.schemas import (
    ExtractionResult, ValidationResult, ReviewConclusion
)

PROMPT_DIR = Path(__file__).parent.parent.parent / "prompts"


class ConclusionSynthesizer:
    """汇总校验结果，生成理赔员可读的综合结论"""

    def __init__(self, client: ModelClient):
        self.client = client
        self._template = (PROMPT_DIR / "conclusion.txt").read_text()

    def synthesize(
        self, extraction: ExtractionResult, validation: ValidationResult
    ) -> ReviewConclusion:
        # 计算风险评分
        risk_score = self._calculate_score(validation)

        # 生成摘要
        report = extraction.report
        medical = extraction.medical

        validation_summary = "\n".join(
            f"- [{i.risk.value.upper()}] {i.dimension}: {i.detail}"
            for i in validation.items
            if i.risk.value in ("red", "yellow")
        )

        prompt = self._template.format(
            disability_level=report.disability_level,
            clause_code=report.applied_clause_code,
            clause_text=report.applied_clause_text,
            discharge_diagnosis="；".join(medical.discharge_diagnosis),
            validation_summary=validation_summary or "未发现明显异常"
        )

        llm_result = self.client.chat_json(
            prompt,
            system_prompt="你是理赔审核专家，只返回JSON。"
        )

        return ReviewConclusion(
            case_id=extraction.case_id,
            risk_score=risk_score,
            risk_level=llm_result["risk_level"],
            abnormal_items=[
                i for i in validation.items
                if i.risk.value in ("red", "yellow")
            ],
            summary=llm_result["summary"],
            suggestion=llm_result["suggestion"],
            extraction=extraction
        )

    @staticmethod
    def _calculate_score(validation: ValidationResult) -> int:
        """
        风险评分规则:
        - 红色项: +20 分/项
        - 黄色项: +5 分/项
        - 上限 100
        """
        score = validation.red_count * 20 + validation.yellow_count * 5
        return min(score, 100)
```

- [ ] **Step 4: 运行测试并提交**

```bash
pytest tests/test_synthesizer.py -v
```

```bash
git add src/synthesizer/ prompts/conclusion.txt tests/test_synthesizer.py
git commit -m "feat: add conclusion synthesizer with risk scoring and LLM summary"
```

---

### Task 6: 主流程编排

**Files:**
- Create: `src/pipeline.py`
- Create: `tests/test_pipeline.py`

**Interfaces:**
- Consumes: 全部模块 (Task 1-5)
- Produces: `InjuryReviewPipeline.review(case_input: CaseInput) -> ReviewConclusion`

- [ ] **Step 1: 编写端到端测试**

```python
# tests/test_pipeline.py
import pytest
from unittest.mock import MagicMock
from src.pipeline import InjuryReviewPipeline
from src.models.schemas import CaseInput, RiskLevel


class TestPipeline:
    def test_end_to_end_suspicious_case(self, sample_case):
        """端到端测试——可疑案件应被标红"""
        mock_client = MagicMock()

        # Mock 阶段一：抽取结果
        mock_client.chat_json.side_effect = [
            # 鉴定报告抽取
            {
                "claimant_name": "张某某", "claimant_age": 45,
                "claimant_gender": "男", "injury_cause": "交通事故",
                "injury_body_parts": ["左膝关节"],
                "injury_date": "2025-08-15", "assessment_date": "2026-02-20",
                "disability_level": 9, "applied_clause_code": "5.9.6.1",
                "applied_clause_text": "一上肢或一下肢三大关节功能丧失50%以上",
                "joint_rom_values": {"左膝关节屈曲": 45.0},
                "muscle_strength_values": {},
                "imaging_findings": "左膝半月板III度损伤"
            },
            # 病历抽取
            {
                "admission_diagnosis": ["左膝关节外伤"],
                "discharge_diagnosis": ["左膝内侧半月板后角损伤（III度）"],
                "surgeries": ["关节镜下半月板缝合术"],
                "imaging_reports": "半月板III度损伤",
                "discharge_function_status": "主动屈曲可达80°",
                "discharge_instructions": "继续康复训练",
                "in_hospital_days": 13
            },
            # 条款匹配度——此处本例应该是匹配的（伤情真实）
            {
                "is_match": True,
                "reasoning": "半月板III度损伤属于膝关节结构损伤，条款引用合理"
            },
            # 综合结论
            {
                "summary": "伤情基础真实，但关节活动度存在15°以上偏差需关注",
                "risk_level": "medium",
                "suggestion": "退回鉴定机构要求说明"
            }
        ]

        pipeline = InjuryReviewPipeline(mock_client)
        case = CaseInput(
            case_id="CASE-001",
            report_text=sample_case["report_text"],
            medical_text=sample_case["medical_text"]
        )

        result = pipeline.review(case)

        assert result.case_id == "CASE-001"
        assert result.risk_score > 0
        assert len(result.abnormal_items) > 0

    def test_end_to_end_normal_case_passes(self, sample_case):
        """端到端测试——无明显异常的完整材料应通过"""
        mock_client = MagicMock()
        mock_client.chat_json.side_effect = [
            {
                "claimant_name": "张某某", "claimant_age": 45,
                "claimant_gender": "男", "injury_cause": "交通事故",
                "injury_body_parts": ["左膝关节"],
                "injury_date": "2025-08-15", "assessment_date": "2026-02-20",
                "disability_level": 9, "applied_clause_code": "5.9.6.1",
                "applied_clause_text": "一上肢或一下肢三大关节功能丧失50%以上",
                "joint_rom_values": {"左膝关节屈曲": 80.0},
                "muscle_strength_values": {},
                "imaging_findings": "半月板III度损伤"
            },
            {
                "admission_diagnosis": ["左膝关节外伤"],
                "discharge_diagnosis": ["左膝内侧半月板后角损伤（III度）"],
                "surgeries": ["半月板缝合术"],
                "imaging_reports": "半月板III度损伤",
                "discharge_function_status": "主动屈曲可达80°",
                "discharge_instructions": "康复训练",
                "in_hospital_days": 13
            },
            {"is_match": True, "reasoning": "匹配"},
            {
                "summary": "所有材料一致，伤情与条款匹配，活动度数值一致",
                "risk_level": "low",
                "suggestion": "通过"
            }
        ]

        pipeline = InjuryReviewPipeline(mock_client)
        case = CaseInput(
            case_id="CASE-002",
            report_text=sample_case["report_text"],
            medical_text=sample_case["medical_text"]
        )

        result = pipeline.review(case)
        assert result.risk_level == "low"
        assert result.suggestion == "通过"
```

- [ ] **Step 2: 实现主流程编排**

```python
# src/pipeline.py
from src.api.model_client import ModelClient
from src.extractors.report_extractor import ReportExtractor
from src.extractors.medical_extractor import MedicalExtractor
from src.validators.clause_matcher import ClauseMatcher
from src.validators.metric_validator import MetricValidator
from src.validators.doc_consistency import DocConsistencyValidator
from src.synthesizer.conclusion import ConclusionSynthesizer
from src.models.schemas import CaseInput, ExtractionResult, ValidationResult, ReviewConclusion


class InjuryReviewPipeline:
    """AI 智能核伤主流程"""

    def __init__(self, client: ModelClient):
        # 阶段一
        self.report_extractor = ReportExtractor(client)
        self.medical_extractor = MedicalExtractor(client)
        # 阶段二
        self.validators = [
            ClauseMatcher(client),
            MetricValidator(),
            DocConsistencyValidator(),
        ]
        # 阶段三
        self.synthesizer = ConclusionSynthesizer(client)

    def review(self, case: CaseInput) -> ReviewConclusion:
        # 阶段一：并行抽取
        report = self.report_extractor.extract(case)
        medical = self.medical_extractor.extract(case)
        extraction = ExtractionResult(
            case_id=case.case_id,
            report=report,
            medical=medical
        )

        # 阶段二：多维校验
        all_items = []
        for validator in self.validators:
            all_items.extend(validator.validate(extraction))

        validation = ValidationResult(
            case_id=case.case_id,
            items=all_items
        )

        # 阶段三：综合结论
        return self.synthesizer.synthesize(extraction, validation)
```

- [ ] **Step 3: 运行测试并提交**

```bash
pytest tests/test_pipeline.py -v
```

```bash
git add src/pipeline.py tests/test_pipeline.py
git commit -m "feat: add main pipeline orchestrating extraction, validation, and conclusion"
```

---

### Task 7: 回溯测试与效果评估

**Files:**
- Create: `evaluation/benchmark.py`
- Create: `evaluation/sample_cases.json`

**Interfaces:**
- Consumes: `InjuryReviewPipeline.review()` (Task 6)
- Produces: 评估报告（准确率、召回率、误伤率）

- [ ] **Step 1: 构造标注样本数据**

```json
[
  {
    "case_id": "CASE-EVAL-001",
    "report_text": "伤者王某某，男，52岁...",
    "medical_text": "入院诊断：右股骨颈骨折...",
    "ground_truth": {
      "is_fraudulent": false,
      "label_note": "真实损伤，评定合理"
    }
  },
  {
    "case_id": "CASE-EVAL-002",
    "report_text": "伤者赵某某，女，38岁...",
    "medical_text": "入院诊断：腰部软组织挫伤...",
    "ground_truth": {
      "is_fraudulent": true,
      "label_note": "软组织挫伤被虚高评为腰椎伤残8级"
    }
  }
]
```

- [ ] **Step 2: 实现回溯测试脚本**

```python
# evaluation/benchmark.py
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from api.model_client import ModelClient
from pipeline import InjuryReviewPipeline
from models.schemas import CaseInput


def load_cases(path: str) -> list[dict]:
    with open(path) as f:
        return json.load(f)


def run_benchmark(cases_path: str) -> dict:
    cases = load_cases(cases_path)
    client = ModelClient()
    pipeline = InjuryReviewPipeline(client)

    results = {
        "total": len(cases),
        "correct": 0,
        "false_positive": 0,   # AI判高风险但实际非欺诈
        "false_negative": 0,   # AI判低风险但实际欺诈
        "details": []
    }

    HIGH_RISK_THRESHOLD = 60

    for case_data in cases:
        case = CaseInput(
            case_id=case_data["case_id"],
            report_text=case_data["report_text"],
            medical_text=case_data["medical_text"],
        )
        conclusion = pipeline.review(case)
        is_fraudulent = case_data["ground_truth"]["is_fraudulent"]
        ai_flagged = conclusion.risk_score >= HIGH_RISK_THRESHOLD

        if ai_flagged == is_fraudulent:
            results["correct"] += 1
        elif ai_flagged and not is_fraudulent:
            results["false_positive"] += 1
        elif not ai_flagged and is_fraudulent:
            results["false_negative"] += 1

        results["details"].append({
            "case_id": case_data["case_id"],
            "risk_score": conclusion.risk_score,
            "risk_level": conclusion.risk_level,
            "suggestion": conclusion.suggestion,
            "ground_truth": case_data["ground_truth"]["is_fraudulent"],
            "correct": ai_flagged == is_fraudulent
        })

    # 计算指标
    total_fraud = sum(1 for c in cases if c["ground_truth"]["is_fraudulent"])
    total_normal = results["total"] - total_fraud

    results["metrics"] = {
        "accuracy": results["correct"] / results["total"],
        "high_risk_recall": (
            (total_fraud - results["false_negative"]) / total_fraud
            if total_fraud > 0 else None
        ),
        "false_positive_rate": (
            results["false_positive"] / total_normal
            if total_normal > 0 else None
        ),
    }

    return results


if __name__ == "__main__":
    import sys
    results = run_benchmark(sys.argv[1] if len(sys.argv) > 1 else "evaluation/sample_cases.json")
    print(f"准确率: {results['metrics']['accuracy']:.1%}")
    print(f"高风险识别率: {results['metrics']['high_risk_recall']:.1%}")
    print(f"误伤率: {results['metrics']['false_positive_rate']:.1%}")
    for d in results["details"]:
        status = "✓" if d["correct"] else "✗"
        print(f"  {status} {d['case_id']}: score={d['risk_score']}, truth={d['ground_truth']}")
```

- [ ] **Step 3: 提交**

```bash
git add evaluation/
git commit -m "feat: add benchmark script and sample evaluation cases"
```

---

### Task 8: 接口层与集成入口

**Files:**
- Create: `src/api/routes.py`（FastAPI 接口）
- Create: `requirements.txt`
- Create: `README.md`

**Interfaces:**
- Consumes: `InjuryReviewPipeline` (Task 6)
- Produces: REST API `POST /review`

- [ ] **Step 1: 编写 FastAPI 接口**

```python
# src/api/routes.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from src.api.model_client import ModelClient
from src.pipeline import InjuryReviewPipeline

app = FastAPI(title="AI 智能核伤")

client = ModelClient()
pipeline = InjuryReviewPipeline(client)


class ReviewRequest(BaseModel):
    case_id: str
    report_text: str
    medical_text: str


@app.post("/review")
def review_injury(request: ReviewRequest):
    """AI 智能核伤主接口——嵌入理赔系统调用"""
    from src.models.schemas import CaseInput
    case = CaseInput(
        case_id=request.case_id,
        report_text=request.report_text,
        medical_text=request.medical_text,
    )
    result = pipeline.review(case)
    return result.model_dump()


@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 2: 编写依赖文件**

```
# requirements.txt
fastapi==0.111.0
uvicorn==0.30.1
pydantic==2.7.0
requests==2.32.0
pytest==8.2.0
```

- [ ] **Step 3: 提交**

```bash
git add src/api/routes.py requirements.txt README.md
git commit -m "feat: add FastAPI interface layer and project dependencies"
```

---

## 开发里程碑与时间线

| 阶段 | 任务 | 工时估算 | 里程碑产物 |
|------|------|---------|-----------|
| 基础建设 | Task 1-2 | 1 天 | 数据模型 + API 客户端可用 |
| 核心能力 | Task 3-5 | 2 天 | 抽取 → 校验 → 结论全链路跑通 |
| 流程串联 | Task 6 | 0.5 天 | 端到端可调用 |
| 效果验证 | Task 7 | 1 天 | 回溯测试报告（50-100 例） |
| 接口集成 | Task 8 | 0.5 天 | REST API 可被理赔系统调用 |
| **总计** | | **5 天** | MVP 交付 |

---

## 风险与应对

| 风险 | 概率 | 影响 | 应对措施 |
|------|------|------|---------|
| LLM 抽取准确率不达标（关节活动度等数值抽取错误） | 中 | 高 | Prompt 中强调"原文摘录，不要改写数值"；增加抽取结果的后置正则校验 |
| 产险大脑 API 响应超时或限流 | 中 | 中 | 客户端内置重试 + 超时降级；理赔员可手动填写结构化表单兜底 |
| 《人体损伤致残程度分级》条款覆盖不全 | 低 | 中 | MVP 先聚焦 3-5 类高频伤情对应条款；后续迭代补全 |
| 病历手写体 OCR 质量差 | 高 | 中 | MVP 仅支持印刷体/电子病历输入；手写体 OCR 列入 V1.0 |
| 理赔员对 AI 结论信任度不足 | 中 | 低 | 每条风险标注出处原文摘引；AI 只标疑不判定，降低抵触 |
