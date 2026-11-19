#模型工厂代码 提供模型
"""
模型工厂
========
对话模型走 DeepSeek（OpenAI 兼容协议），向量化走本地 sentence-transformers（BGE）。

为什么这么拆：
- DeepSeek 只提供对话接口，没有 embedding，也没有语音，所以向量化必须落在本地模型上。
- 向量化统一收敛到 embedding_model 一个实例，避免各模块各自指定维度导致 Chroma 集合冲突。

配置来源：config/rag.yml
    chat_model_name      对话模型名，默认 deepseek-chat
    base_url             兼容端点，默认 https://api.deepseek.com/v1
    embedding_model_name 本地向量模型，默认 BAAI/bge-small-zh-v1.5
密钥来源（按优先级）：
    1. 环境变量 DEEPSEEK_API_KEY（CI 或临时注入）
    2. Windows DPAPI 加密存储（ai/scripts/set_api_key.py 写入，绑定当前 Windows 账号）
项目里不保留任何明文密钥文件。
"""
import os
from abc import ABC, abstractmethod
from typing import Optional

from langchain_core.embeddings import Embeddings
from langchain_core.language_models import BaseChatModel
from langchain_openai import ChatOpenAI

from utils.config_handler import rag_conf

# DeepSeek 的 OpenAI 兼容端点
DEFAULT_BASE_URL = "https://api.deepseek.com/v1"
DEFAULT_CHAT_MODEL = "deepseek-chat"
DEFAULT_EMBEDDING_MODEL = "BAAI/bge-small-zh-v1.5"

SECRET_NAME = "deepseek"


def get_llm_api_key() -> str:
    """对话模型密钥：环境变量优先，其次 DPAPI 加密存储。"""
    key = (os.environ.get("DEEPSEEK_API_KEY") or "").strip()
    if key:
        return key
    try:
        from utils.secrets import load_secret

        return (load_secret(SECRET_NAME) or "").strip()
    except Exception:
        return ""


def has_llm_key() -> bool:
    """是否配置了对话模型密钥。供各模块决定走大模型还是本地规则兜底。"""
    return bool(get_llm_api_key())


def create_chat_model(model_name: Optional[str] = None, **kwargs) -> BaseChatModel:
    """
    统一创建对话模型实例。所有模块都应通过这里取模型，不要各自实例化。

    兼容处理：历史配置/调用点可能仍传 qwen-*/tongyi 之类的模型名，
    这类名字在 DeepSeek 端点下会 404，因此统一映射到默认模型。
    """
    name = (model_name or rag_conf.get("chat_model_name") or DEFAULT_CHAT_MODEL).strip()
    if not name.lower().startswith("deepseek"):
        name = DEFAULT_CHAT_MODEL

    return ChatOpenAI(
        model=name,
        # 无 key 时给个占位值，让构造不被校验拦下，真正调用时再抛 401，错误信息更直观
        api_key=get_llm_api_key() or "EMPTY",
        base_url=str(rag_conf.get("base_url") or DEFAULT_BASE_URL),
        temperature=kwargs.pop("temperature", 0.3),
        timeout=kwargs.pop("timeout", 120),
        max_retries=kwargs.pop("max_retries", 1),
        **kwargs,
    )


# 抽象工厂类: 强制统一接口（规范）
class BaseModelFactory(ABC):
    @abstractmethod
    def generator(self) -> Optional[Embeddings | BaseChatModel]:
        pass


class ChatModelFactory(BaseModelFactory):
    def generator(self) -> Optional[Embeddings | BaseChatModel]:
        return create_chat_model()


class _LazyHuggingFaceEmbeddings(Embeddings):
    """
    本地向量模型，首次使用时才加载。

    不在模块导入阶段加载的原因：模型约 100MB，若在 import 时就下载/加载，
    脚本、单元测试、只跑其中某个路由的场景都会被拖慢甚至因网络失败而整体起不来。
    """

    def __init__(self) -> None:
        self._impl = None

    def _load(self):
        if self._impl is None:
            # huggingface.co 在部分网络下不可达，默认走镜像；已设置则尊重用户配置
            os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")
            try:
                from langchain_huggingface import HuggingFaceEmbeddings
            except ImportError:
                from langchain_community.embeddings import HuggingFaceEmbeddings

            self._impl = HuggingFaceEmbeddings(
                model_name=rag_conf.get("embedding_model_name") or DEFAULT_EMBEDDING_MODEL,
                model_kwargs={"device": "cpu"},
                encode_kwargs={"normalize_embeddings": True},
            )
        return self._impl

    def embed_documents(self, texts):
        return self._load().embed_documents(texts)

    def embed_query(self, text):
        return self._load().embed_query(text)


class EmbeddingsFactory(BaseModelFactory):
    def generator(self) -> Optional[Embeddings | BaseChatModel]:
        return _LazyHuggingFaceEmbeddings()


chat_model = ChatModelFactory().generator()
embedding_model = EmbeddingsFactory().generator()
